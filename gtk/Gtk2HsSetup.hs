{-# LANGUAGE CPP #-}

#define CABAL_VERSION_ENCODE(major, minor, micro) (     \
          ((major) * 10000)                             \
        + ((minor) *   100)                             \
        + ((micro) *     1))

#define CABAL_VERSION_CHECK(major,minor,micro)    \
        (CABAL_VERSION >= CABAL_VERSION_ENCODE(major,minor,micro))

-- now, this is bad, but Cabal doesn't seem to actually pass any information about
-- its version to CPP, so guess the version depending on the version of GHC
#ifdef CABAL_VERSION_MINOR
#ifndef CABAL_VERSION_MAJOR
#define CABAL_VERSION_MAJOR 1
#endif
#ifndef CABAL_VERSION_MICRO
#define CABAL_VERSION_MICRO 0
#endif
#define CABAL_VERSION CABAL_VERSION_ENCODE(     \
        CABAL_VERSION_MAJOR,                    \
        CABAL_VERSION_MINOR,                    \
        CABAL_VERSION_MICRO)
#else
#warning Setup.hs is guessing the version of Cabal. If compilation of Setup.hs fails use -DCABAL_VERSION_MINOR=x for Cabal version 1.x.0 when building (prefixed by --ghc-option= when using the 'cabal' command)
#if (__GLASGOW_HASKELL__ >= 612)
#define CABAL_VERSION CABAL_VERSION_ENCODE(1,8,0)
#else
#define CABAL_VERSION CABAL_VERSION_ENCODE(1,6,0)
#endif
#endif

-- | Build a Gtk2hs package.
--
module Gtk2HsSetup ( 
  gtk2hsUserHooks, 
  getPkgConfigPackages, 
  checkGtk2hsBuildtools
  ) where

import Distribution.Simple
import Distribution.Simple.PreProcess
import Distribution.InstalledPackageInfo ( importDirs,
                                           showInstalledPackageInfo,
                                           libraryDirs,
                                           extraLibraries,
                                           extraGHCiLibraries )
import Distribution.Simple.PackageIndex (
#if CABAL_VERSION_CHECK(1,8,0)
  lookupInstalledPackageId
#else
  lookupPackageId
#endif
  )
import Distribution.PackageDescription as PD ( PackageDescription(..),
                                               updatePackageDescription,
                                               BuildInfo(..),
                                               emptyBuildInfo, allBuildInfo,
                                               Library(..),
                                               libModules, hasLibs)
import Distribution.Simple.LocalBuildInfo (LocalBuildInfo(..),
                                           InstallDirs(..),
#if CABAL_VERSION_CHECK(1,8,0)
                                           componentPackageDeps,
#else
                                           packageDeps,
#endif
                                           absoluteInstallDirs)
import Distribution.Simple.Compiler  ( Compiler(..) )
import Distribution.Simple.Program (
  Program(..), ConfiguredProgram(..),
  rawSystemProgramConf, rawSystemProgramStdoutConf, programName,
  c2hsProgram, pkgConfigProgram, requireProgram, ghcPkgProgram,
  simpleProgram, lookupProgram, rawSystemProgramStdout, ProgArg)
import Distribution.ModuleName ( ModuleName, components, toFilePath )
import Distribution.Simple.Utils
import Distribution.Simple.Setup (CopyFlags(..), InstallFlags(..), CopyDest(..),
                                  defaultCopyFlags, ConfigFlags(configVerbosity),
                                  fromFlag, toFlag, RegisterFlags(..), flagToMaybe,
                                  fromFlagOrDefault, defaultRegisterFlags)
import Distribution.Simple.BuildPaths ( autogenModulesDir )
import Distribution.Simple.Install ( install )
#if CABAL_VERSION_CHECK(1,8,0)
import Distribution.Simple.Register ( generateRegistrationInfo, registerPackage )
#else
import qualified Distribution.Simple.Register as Register ( register )
#endif
import Distribution.Text ( simpleParse, display )
import System.FilePath
import System.Directory ( doesFileExist, getDirectoryContents, getDirectoryContents, doesDirectoryExist )
import Distribution.Version (Version(..))
import Distribution.Verbosity
import Control.Monad (when, unless, filterM, liftM, forM)
import Data.Maybe ( isJust, isNothing, fromMaybe, maybeToList )
import Data.List (isPrefixOf, isSuffixOf, nub)
import Data.Char (isAlpha)
import qualified Data.Map as M
import qualified Data.Set as S

import Control.Applicative ((<$>))

-- the name of the c2hs pre-compiled header file
precompFile = "precompchs.bin"

gtk2hsUserHooks = simpleUserHooks {
    hookedPrograms = [typeGenProgram, signalGenProgram, c2hsLocal],
    hookedPreProcessors = [("chs", ourC2hs)],
    confHook = \pd cf ->
      confHook simpleUserHooks pd cf >>= return . adjustLocalBuildInfo,
    postConf = \args cf pd lbi -> do
      genSynthezisedFiles (fromFlag (configVerbosity cf)) pd lbi
      postConf simpleUserHooks args cf pd lbi,
    buildHook = \pd lbi uh bf -> fixDeps pd >>= \pd ->
                                 (buildHook simpleUserHooks) pd lbi uh bf,
    copyHook = \pd lbi uh flags -> (copyHook simpleUserHooks) pd lbi uh flags >>
      installCHI pd lbi (fromFlag (copyVerbosity flags)) (fromFlag (copyDest flags)),
    instHook = \pd lbi uh flags ->
#if defined(mingw32_HOST_OS) || defined(__MINGW32__)
      installHook pd lbi uh flags >>
      installCHI pd lbi (fromFlag (installVerbosity flags)) NoCopyDest,
    regHook = registerHook
#else
      instHook simpleUserHooks pd lbi uh flags >>
      installCHI pd lbi (fromFlag (installVerbosity flags)) NoCopyDest
#endif
  }

------------------------------------------------------------------------------
-- Lots of stuff for windows ghci support
------------------------------------------------------------------------------

getDlls :: [FilePath] -> IO [FilePath]
getDlls dirs = filter ((== ".dll") . takeExtension) . concat <$>
    mapM getDirectoryContents dirs

fixLibs :: [FilePath] -> [String] -> [String]
fixLibs dlls = concatMap $ \ lib ->
    case filter (("lib" ++ lib) `isPrefixOf`) dlls of
                dll:_ -> [dropExtension dll]
                _     -> if lib == "z" then [] else [lib]

-- The following code is a big copy-and-paste job from the sources of
-- Cabal 1.8 just to be able to fix a field in the package file. Yuck.

#if CABAL_VERSION_CHECK(1,8,0)
        
installHook :: PackageDescription -> LocalBuildInfo
                   -> UserHooks -> InstallFlags -> IO ()
installHook pkg_descr localbuildinfo _ flags = do
  let copyFlags = defaultCopyFlags {
                      copyDistPref   = installDistPref flags,
                      copyDest       = toFlag NoCopyDest,
                      copyVerbosity  = installVerbosity flags
                  }
  install pkg_descr localbuildinfo copyFlags
  let registerFlags = defaultRegisterFlags {
                          regDistPref  = installDistPref flags,
                          regInPlace   = installInPlace flags,
                          regPackageDB = installPackageDB flags,
                          regVerbosity = installVerbosity flags
                      }
  when (hasLibs pkg_descr) $ register pkg_descr localbuildinfo registerFlags

registerHook :: PackageDescription -> LocalBuildInfo
        -> UserHooks -> RegisterFlags -> IO ()
registerHook pkg_descr localbuildinfo _ flags =
    if hasLibs pkg_descr
    then register pkg_descr localbuildinfo flags
    else setupMessage verbosity
           "Package contains no library to register:" (packageId pkg_descr)
  where verbosity = fromFlag (regVerbosity flags)

register :: PackageDescription -> LocalBuildInfo
         -> RegisterFlags -- ^Install in the user's database?; verbose
         -> IO ()
register pkg@PackageDescription { library       = Just lib  }
         lbi@LocalBuildInfo     { libraryConfig = Just clbi } regFlags
  = do

    installedPkgInfoRaw <- generateRegistrationInfo
                           verbosity pkg lib lbi clbi inplace distPref

    dllsInScope <- getSearchPath >>= (filterM doesDirectoryExist) >>= getDlls
    let libs = fixLibs dllsInScope (extraLibraries installedPkgInfoRaw)
        installedPkgInfo = installedPkgInfoRaw {
                                extraGHCiLibraries = libs }

     -- Three different modes:
    case () of
     _ | modeGenerateRegFile   -> die "Generate Reg File not supported"
       | modeGenerateRegScript -> die "Generate Reg Script not supported"
       | otherwise             -> registerPackage verbosity
                                    installedPkgInfo pkg lbi inplace packageDb

  where
    modeGenerateRegFile = isJust (flagToMaybe (regGenPkgConf regFlags))
    modeGenerateRegScript = fromFlag (regGenScript regFlags)
    inplace   = fromFlag (regInPlace regFlags)
    packageDb = case flagToMaybe (regPackageDB regFlags) of
                    Just db -> db
                    Nothing -> registrationPackageDB (withPackageDB lbi)
    distPref  = fromFlag (regDistPref regFlags)
    verbosity = fromFlag (regVerbosity regFlags)

register _ _ regFlags = notice verbosity "No package to register"
  where
    verbosity = fromFlag (regVerbosity regFlags)

#else
installHook :: PackageDescription -> LocalBuildInfo
                   -> UserHooks -> InstallFlags -> IO ()
installHook pkg_descr localbuildinfo _ flags = do
  let copyFlags = defaultCopyFlags {
                      copyDistPref   = installDistPref flags,
                      copyInPlace    = installInPlace flags,
                      copyUseWrapper = installUseWrapper flags,
                      copyDest       = toFlag NoCopyDest,
                      copyVerbosity  = installVerbosity flags
                  }
  install pkg_descr localbuildinfo copyFlags
  let registerFlags = defaultRegisterFlags {
                          regDistPref  = installDistPref flags,
                          regInPlace   = installInPlace flags,
                          regPackageDB = installPackageDB flags,
                          regVerbosity = installVerbosity flags
                      }
  when (hasLibs pkg_descr) $ register pkg_descr localbuildinfo registerFlags

registerHook :: PackageDescription -> LocalBuildInfo
        -> UserHooks -> RegisterFlags -> IO ()
registerHook pkg_descr localbuildinfo _ flags =
    if hasLibs pkg_descr
    then register pkg_descr localbuildinfo flags
    else setupMessage verbosity
           "Package contains no library to register:" (packageId pkg_descr)
  where verbosity = fromFlag (regVerbosity flags)

register :: PackageDescription -> LocalBuildInfo
         -> RegisterFlags -- ^Install in the user's database?; verbose
         -> IO ()
register pkg_descr lbi regFlags = do
  let verbosity = fromFlag (regVerbosity regFlags)
  warn verbosity "Cannot register ghci libraries with Cabal 1.6 (need 1.8)."
  Register.register pkg_descr lbi regFlags
  
#endif

------------------------------------------------------------------------------
-- This is a hack for Cabal-1.8, It is not needed in Cabal-1.9.1 or later
------------------------------------------------------------------------------

adjustLocalBuildInfo :: LocalBuildInfo -> LocalBuildInfo
adjustLocalBuildInfo lbi =
  let extra = (Just libBi, [])
      libBi = emptyBuildInfo { includeDirs = [ autogenModulesDir lbi
                                             , buildDir lbi ] }
   in lbi { localPkgDescr = updatePackageDescription extra (localPkgDescr lbi) }

------------------------------------------------------------------------------
-- Processing .chs files with our local c2hs.
------------------------------------------------------------------------------

ourC2hs :: BuildInfo -> LocalBuildInfo -> PreProcessor
ourC2hs bi lbi = PreProcessor {
  platformIndependent = False,
  runPreProcessor = runC2HS bi lbi
}

runC2HS :: BuildInfo -> LocalBuildInfo ->
           (FilePath, FilePath) -> (FilePath, FilePath) -> Verbosity -> IO ()
runC2HS bi lbi (inDir, inFile)  (outDir, outFile) verbosity = do
  -- have the header file name if we don't have the precompiled header yet
  header <- case lookup "x-c2hs-header" (customFieldsBI bi) of
    Just h -> return h
    Nothing -> die ("Need x-c2hs-Header definition in the .cabal Library section "++
                    "that sets the C header file to process .chs.pp files.")

  -- c2hs will output files in out dir, removing any leading path of the input file.
  -- Thus, append the dir of the input file to the output dir.
  let (outFileDir, newOutFile) = splitFileName outFile
  let newOutDir = outDir </> outFileDir
  -- additional .chi files might be needed that other packages have installed;
  -- we assume that these are installed in the same place as .hi files
  let chiDirs = [ dir |
#if CABAL_VERSION_CHECK(1,8,0)
                  ipi <- maybe [] (map fst . componentPackageDeps) (libraryConfig lbi),
                  dir <- maybe [] importDirs (lookupInstalledPackageId (installedPkgs lbi) ipi) ]
#else
                  ipi <- packageDeps lbi,
                  dir <- maybe [] importDirs (lookupPackageId (installedPkgs lbi) ipi) ]
#endif
  rawSystemProgramConf verbosity c2hsLocal (withPrograms lbi) $
       map ("--include=" ++) (outDir:chiDirs)
    ++ ["--cppopts=" ++ opt | opt <- getCppOptions bi lbi]
    ++ ["--output-dir=" ++ newOutDir,
        "--output=" ++ newOutFile,
        "--precomp=" ++ buildDir lbi </> precompFile,
        header, inDir </> inFile]

getCppOptions :: BuildInfo -> LocalBuildInfo -> [String]
getCppOptions bi lbi
    = nub $
      ["-I" ++ dir | dir <- PD.includeDirs bi]
   ++ [opt | opt@('-':c:_) <- (PD.cppOptions bi ++ PD.ccOptions bi), c `elem` "DIU"]

installCHI :: PackageDescription -- ^information from the .cabal file
        -> LocalBuildInfo -- ^information from the configure step
        -> Verbosity -> CopyDest -- ^flags sent to copy or install
        -> IO ()
installCHI pkg@PD.PackageDescription { library = Just lib } lbi verbosity copydest = do
  let InstallDirs { libdir = libPref } = absoluteInstallDirs pkg lbi copydest
  -- cannot use the recommended 'findModuleFiles' since it fails if there exists
  -- a modules that does not have a .chi file
  mFiles <- mapM (findFileWithExtension' ["chi"] [buildDir lbi])
                 (map toFilePath
#if CABAL_VERSION_CHECK(1,8,0)
                   (PD.libModules lib)
#else
                   (PD.libModules pkg)
#endif
                 )
  let files = [ f | Just f <- mFiles ]
#if CABAL_VERSION_CHECK(1,8,0)
  installOrdinaryFiles verbosity libPref files
#else
  copyFiles verbosity libPref files
#endif

  
installCHI _ _ _ _ = return ()

------------------------------------------------------------------------------
-- Generating the type hierarchy and signal callback .hs files.
------------------------------------------------------------------------------

typeGenProgram :: Program
typeGenProgram = (simpleProgram "gtk2hsTypeGen")

signalGenProgram :: Program
signalGenProgram = (simpleProgram "gtk2hsHookGenerator")

c2hsLocal :: Program
c2hsLocal = (simpleProgram "gtk2hsC2hs")

genSynthezisedFiles :: Verbosity -> PackageDescription -> LocalBuildInfo -> IO ()
genSynthezisedFiles verb pd lbi = do

  cPkgs <- getPkgConfigPackages verb lbi pd

  let xList = maybe [] (customFieldsBI . libBuildInfo) (library pd)
              ++customFieldsPD pd
      typeOpts :: String -> [ProgArg]
      typeOpts tag = concat [ map (\val -> '-':'-':drop (length tag) field++'=':val) (words content)
                            | (field,content) <- xList,
                              tag `isPrefixOf` field,
                              field /= (tag++"file")]
              ++ [ "--tag=" ++ tag
                 | PackageIdentifier name (Version (major:minor:_) _) <- cPkgs
                 , let name' = filter isAlpha (display name)
                 , tag <- name'
                        : [ name' ++ "-" ++ show major ++ "." ++ show digit
                          | digit <- [0,2..minor] ]
                 ]

      signalsOpts :: [ProgArg]
      signalsOpts = concat [ map (\val -> '-':'-':drop 10 field++'=':val) (words content)
                        | (field,content) <- xList,
                          "x-signals-" `isPrefixOf` field,
                          field /= "x-signals-file"]

      genFile :: Program -> [ProgArg] -> FilePath -> IO ()
      genFile prog args outFile = do
         res <- rawSystemProgramStdoutConf verb prog (withPrograms lbi) args
         rewriteFile outFile res

  (flip mapM_) (filter (\(tag,_) -> "x-types-" `isPrefixOf` tag && "file" `isSuffixOf` tag) xList) $
    \(fileTag, f) -> do
      let tag = reverse (drop 4 (reverse fileTag))
      info verb ("Ensuring that class hierarchy in "++f++" is up-to-date.")
      genFile typeGenProgram (typeOpts tag) f

  case lookup "x-signals-file" xList of
    Nothing -> return ()
    Just f -> do
      info verb ("Ensuring that callback hooks in "++f++" are up-to-date.")
      genFile signalGenProgram signalsOpts f

--FIXME: Cabal should tell us the selected pkg-config package versions in the
--       LocalBuildInfo or equivalent.
--       In the mean time, ask pkg-config again.

getPkgConfigPackages :: Verbosity -> LocalBuildInfo -> PackageDescription -> IO [PackageId]
getPkgConfigPackages verbosity lbi pkg =
  sequence
    [ do version <- pkgconfig ["--modversion", display pkgname]
         case simpleParse version of
           Nothing -> die $ "parsing output of pkg-config --modversion failed"
           Just v  -> return (PackageIdentifier pkgname v)
    | Dependency pkgname _ <- concatMap pkgconfigDepends (allBuildInfo pkg) ]
  where
    pkgconfig = rawSystemProgramStdoutConf verbosity
                  pkgConfigProgram (withPrograms lbi)

------------------------------------------------------------------------------
-- Dependency calculation amongst .chs files.
------------------------------------------------------------------------------

-- Given all files of the package, find those that end in .chs and extract the
-- .chs files they depend upon. Then return the PackageDescription with these
-- files rearranged so that they are built in a sequence that files that are
-- needed by other files are built first.
fixDeps :: PackageDescription -> IO PackageDescription
fixDeps pd@PD.PackageDescription {
          PD.library = Just lib@PD.Library {
            PD.exposedModules = expMods,
            PD.libBuildInfo = bi@PD.BuildInfo {
              PD.hsSourceDirs = srcDirs,
              PD.otherModules = othMods
            }}} = do
  let findModule m = findFileWithExtension [".chs.pp",".chs"] srcDirs
                       (joinPath (components m))
  mExpFiles <- mapM findModule expMods
  mOthFiles <- mapM findModule othMods

  -- tag all exposed files with True so we throw an error if we need to build
  -- an exposed module before an internal modules (we cannot express this)
  let modDeps = zipWith (ModDep True []) expMods mExpFiles++
                zipWith (ModDep False []) othMods mOthFiles
  modDeps <- mapM extractDeps modDeps
  let (expMods, othMods) = span mdExposed $ sortTopological modDeps
      badOther = map (fromMaybe "<no file>" . mdLocation) $
                 filter (not . mdExposed) expMods
  unless (null badOther) $
    die ("internal chs modules "++intercalate "," badOther++
         " depend on exposed chs modules; cabal needs to build internal modules first")
  return pd { PD.library = Just lib {
    PD.exposedModules = map mdOriginal expMods,
    PD.libBuildInfo = bi { PD.otherModules = map mdOriginal othMods }
  }}

data ModDep = ModDep {
  mdExposed :: Bool,
  mdRequires :: [ModuleName],
  mdOriginal :: ModuleName,
  mdLocation :: Maybe FilePath
}

instance Show ModDep where
  show x = show (mdLocation x)

instance Eq ModDep where
  ModDep { mdOriginal = m1 } == ModDep { mdOriginal = m2 } = m1==m2
instance Ord ModDep where
  compare ModDep { mdOriginal = m1 } ModDep { mdOriginal = m2 } = compare m1 m2

-- Extract the dependencies of this file. This is intentionally rather naive as it
-- ignores CPP conditionals. We just require everything which means that the
-- existance of a .chs module may not depend on some CPP condition.  
extractDeps :: ModDep -> IO ModDep
extractDeps md@ModDep { mdLocation = Nothing } = return md
extractDeps md@ModDep { mdLocation = Just f } = withUTF8FileContents f $ \con -> do
  let findImports acc (('{':'#':xs):xxs) = case (dropWhile ((==) ' ') xs) of
        ('i':'m':'p':'o':'r':'t':' ':ys) ->
          case simpleParse (takeWhile ((/=) '#') ys) of
            Just m -> findImports (m:acc) xxs 
            Nothing -> die ("cannot parse chs import in "++f++":\n"++
                            "offending line is {#"++xs)
         -- no more imports after the first non-import hook
        _ -> return acc
      findImports acc (_:xxs) = findImports acc xxs
      findImports acc [] = return acc
  mods <- findImports [] (lines con)
  return md { mdRequires = mods }

-- Find a total order of the set of modules that are partially sorted by their
-- dependencies on each other. The function returns the sorted list of modules
-- together with a list of modules that are required but not supplied by this
-- in the input set of modules.
sortTopological :: [ModDep] -> [ModDep]
sortTopological ms = reverse $ fst $ foldl visit ([], S.empty) (map mdOriginal ms)
  where
  set = M.fromList (map (\m -> (mdOriginal m, m)) ms)
  visit (out,visited) m
    | m `S.member` visited = (out,visited)
    | otherwise = case m `M.lookup` set of
        Nothing -> (out, m `S.insert` visited)
        Just md -> (md:out', visited')
          where
            (out',visited') = foldl visit (out, m `S.insert` visited) (mdRequires md)

-- Check user whether install gtk2hs-buildtools correctly.
checkGtk2hsBuildtools :: IO ()
checkGtk2hsBuildtools = do
  allExecuteFiles <- getAllExecuteFiles
  let c2hsName          = programName c2hsLocal
      typeProgramName   = programName typeGenProgram
      signalProgramName = programName signalGenProgram
      printError name = do
        error $ "Can't found " ++ name ++ "\n" 
                   ++ "Please install package `gtk2hs-buildtools` first, and make sure " ++ name ++ " in your PATH."
  if not (c2hsName `elem` allExecuteFiles)
     then printError c2hsName
     else if not (typeProgramName `elem` allExecuteFiles)
          then printError typeProgramName
          else if not (signalProgramName `elem` allExecuteFiles)
               then printError signalProgramName
               else return ()

-- Get all execute files.
getAllExecuteFiles :: IO [String]
getAllExecuteFiles = do
  paths <- getSearchPath
  liftM concat $ forM paths getDirectoryContents
