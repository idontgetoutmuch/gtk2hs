-- GIMP Toolkit (GTK) Binding for Haskell: binding to gstreamer   -*-haskell-*-
--
--  Author : Peter Gavin
--  Created: 1-Apr-2007
--
--  Copyright (c) 2007 Peter Gavin
--
--  This library is free software; you can redistribute it and/or
--  modify it under the terms of the GNU Library General Public
--  License as published by the Free Software Foundation; either
--  version 2 of the License, or (at your option) any later version.
--
--  This library is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
--  Library General Public License for more details.
--
module Media.Streaming.GStreamer.Parse (
  parseLaunch,
  parseLaunchFromArgs,
  parseBinFromDescription
  ) where

{#import Media.Streaming.GStreamer.Types#}
import System.Glib.GError
import System.Glib.UTFString
import System.Glib.FFI

{# context lib = "gstreamer" prefix = "gst" #}

parseLaunch :: String
            -> IO (Maybe Element, Maybe GError)
parseLaunch pipelineDescription =
    withUTFString pipelineDescription $ \cPipelineDescription ->
        alloca $ \gErrorPtr ->
            do element <- {# call parse_launch #} cPipelineDescription (castPtr gErrorPtr) >>=
                              maybePeek newElement
               gError <- peek gErrorPtr >>= maybePeek peek
               return (element, gError)

parseLaunchFromArgs :: [String]
                    -> IO (Maybe Element, Maybe GError)
parseLaunchFromArgs args =
    withUTFStringArray0 args $ \cArgs ->
        alloca $ \gErrorPtr ->
            do element <- {# call parse_launchv #} (castPtr cArgs) (castPtr gErrorPtr) >>=
                              maybePeek newElement
               gError <- peek gErrorPtr >>= maybePeek peek
               return (element, gError)

parseBinFromDescription :: String
                        -> Bool
                        -> IO (Maybe Element, Maybe GError)
parseBinFromDescription binDescription ghostUnconnectedPads =
    withUTFString binDescription $ \cBinDescription ->
        alloca $ \gErrorPtr ->
            do element <- {# call parse_bin_from_description #} cBinDescription
                                                                (fromBool ghostUnconnectedPads)
                                                                (castPtr gErrorPtr) >>=
                              maybePeek newElement
               gError <- peek gErrorPtr >>= maybePeek peek
               return (element, gError)
