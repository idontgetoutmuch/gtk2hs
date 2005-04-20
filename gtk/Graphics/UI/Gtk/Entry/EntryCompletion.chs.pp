-- -*-haskell-*-
--  GIMP Toolkit (GTK) Widget EntryCompletion
--
--  Author : Duncan Coutts
--
--  Created: 24 April 2004
--
--  Version $Revision: 1.11 $ from $Date: 2005/04/20 03:55:39 $
--
--  Copyright (C) 2004-2005 Duncan Coutts
--
--  This library is free software; you can redistribute it and/or
--  modify it under the terms of the GNU Lesser General Public
--  License as published by the Free Software Foundation; either
--  version 2.1 of the License, or (at your option) any later version.
--
--  This library is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
--  Lesser General Public License for more details.
--
-- |
-- Maintainer  : gtk2hs-users@lists.sourceforge.net
-- Stability   : provisional
-- Portability : portable (depends on GHC)
--
-- Completion functionality for 'Entry'
--
-- * Module available since Gtk+ version 2.4
--
module Graphics.UI.Gtk.Entry.EntryCompletion (
-- * Detail
-- 
-- | 'EntryCompletion' is an auxiliary object to be used in conjunction with
-- 'Entry' to provide the completion functionality. It implements the
-- 'CellLayout' interface, to allow the user to add extra cells to the
-- 'TreeView' with completion matches.
--
-- \"Completion functionality\" means that when the user modifies the text
-- in the entry, 'EntryCompletion' checks which rows in the model match the
-- current content of the entry, and displays a list of matches. By default,
-- the matching is done by comparing the entry text case-insensitively against
-- the text column of the model (see 'entryCompletionSetTextColumn'), but this
-- can be overridden with a custom match function (see
-- 'entryCompletionSetMatchFunc').
--
-- When the user selects a completion, the content of the entry is updated.
-- By default, the content of the entry is replaced by the text column of the
-- model, but this can be overridden by connecting to the ::match-selected
-- signal and updating the entry in the signal handler. Note that you should
-- return @True@ from the signal handler to suppress the default behaviour.
--
-- To add completion functionality to an entry, use 'entrySetCompletion'.
--
-- In addition to regular completion matches, which will be inserted into
-- the entry when they are selected, 'EntryCompletion' also allows to display
-- \"actions\" in the popup window. Their appearance is similar to menuitems,
-- to differentiate them clearly from completion strings. When an action is
-- selected, the ::action-activated signal is emitted.

-- * Class Hierarchy
-- |
-- @
-- |  'GObject'
-- |   +----EntryCompletion
-- @

#if GTK_CHECK_VERSION(2,4,0)
-- * Types
  EntryCompletion,
  EntryCompletionClass,
  castToEntryCompletion,

-- * Constructors
  entryCompletionNew,

-- * Methods
  entryCompletionGetEntry,
  entryCompletionSetModel,
  entryCompletionGetModel,
  entryCompletionSetMatchFunc,
  entryCompletionSetMinimumKeyLength,
  entryCompletionGetMinimumKeyLength,
  entryCompletionComplete,
  entryCompletionInsertActionText,
  entryCompletionInsertActionMarkup,
  entryCompletionDeleteAction,
  entryCompletionSetTextColumn,
#if GTK_CHECK_VERSION(2,6,0)
  entryCompletionInsertPrefix,
  entryCompletionGetTextColumn,
  entryCompletionSetInlineCompletion,
  entryCompletionGetInlineCompletion,
  entryCompletionSetPopupCompletion,
  entryCompletionGetPopupCompletion,
#endif

-- * Properties
  entryCompletionMinimumKeyLength,
#if GTK_CHECK_VERSION(2,6,0)
  entryCompletionTextColumn,
  entryCompletionInlineCompletion,
  entryCompletionPopupCompletion,
#endif

-- * Signals
#if GTK_CHECK_VERSION(2,6,0)
  onInsertPrefix,
  afterInsertPrefix,
#endif
  onActionActivated,
  afterActionActivated,
#endif
  ) where

import Monad	(liftM)
import Data.IORef (newIORef, readIORef, writeIORef)

import System.Glib.FFI
import System.Glib.UTFString
import System.Glib.Attributes		(Attr(..))
import System.Glib.GObject		(makeNewGObject, mkFunPtrDestructor)
import Graphics.UI.Gtk.Abstract.Object  (makeNewObject)
{#import Graphics.UI.Gtk.Types#}
{#import Graphics.UI.Gtk.Signals#}
{#import Graphics.UI.Gtk.TreeList.TreeIter#} (TreeIter, createTreeIter)

{# context lib="gtk" prefix="gtk" #}

#if GTK_CHECK_VERSION(2,4,0)
--------------------
-- Constructors

-- | Creates a new 'EntryCompletion' object.
--
entryCompletionNew :: IO EntryCompletion
entryCompletionNew =
  makeNewGObject mkEntryCompletion $
  {# call gtk_entry_completion_new #}

--------------------
-- Methods

-- | Gets the entry @completion@ has been attached to.
--
entryCompletionGetEntry :: EntryCompletion
 -> IO (Maybe Widget) -- ^ returns the entry @completion@ has been attached
                      -- to.
entryCompletionGetEntry self =
  maybeNull (makeNewObject mkWidget) $
  {# call gtk_entry_completion_get_entry #}
    self

-- | Sets the model for a 'EntryCompletion'. If @completion@ already has a
-- model set, it will remove it before setting the new model. If model is
-- @Nothing@, then it will unset the model.
--
entryCompletionSetModel :: TreeModelClass model => EntryCompletion
 -> Maybe model     -- ^ @model@ - The 'TreeModel'.
 -> IO ()
entryCompletionSetModel self model =
  {# call gtk_entry_completion_set_model #}
    self
    (maybe (TreeModel nullForeignPtr) toTreeModel model)

-- | Returns the model the 'EntryCompletion' is using as data source. Returns
-- @Nothing@ if the model is unset.
--
entryCompletionGetModel :: EntryCompletion
 -> IO (Maybe TreeModel) -- ^ returns A 'TreeModel', or @Nothing@ if none is
                         -- currently being used.
entryCompletionGetModel self =
  maybeNull (makeNewGObject mkTreeModel) $
  {# call gtk_entry_completion_get_model #}
    self

-- | Sets the match function for @completion@ to be @func@. The match function
-- is used to determine if a row should or should not be in the completion
-- list.
--
entryCompletionSetMatchFunc :: EntryCompletion -> (String -> TreeIter -> IO ()) -> IO ()
entryCompletionSetMatchFunc ec handler = do
  hPtr <- mkHandler_GtkEntryCompletionMatchFunc
    (\_ keyPtr iterPtr _ -> do key <- peekUTFString keyPtr
                               iter <- createTreeIter iterPtr
                               handler key iter)
  dPtr <- mkFunPtrDestructor hPtr
  {# call gtk_entry_completion_set_match_func #} ec
    (castFunPtr hPtr) nullPtr dPtr

-------------------------------------------------
-- Callback stuff for entryCompletionSetMatchFunc
--

type GtkEntryCompletionMatchFunc =
  Ptr EntryCompletion -> --GtkEntryCompletion *completion
  Ptr CChar ->           --const gchar *key
  Ptr TreeIter ->        --GtkTreeIter *iter
  Ptr () ->              --gpointer user_data
  IO ()

foreign import ccall "wrapper" mkHandler_GtkEntryCompletionMatchFunc ::
  GtkEntryCompletionMatchFunc -> 
  IO (FunPtr GtkEntryCompletionMatchFunc)

-- | Requires the length of the search key for @completion@ to be at least
-- @length@. This is useful for long lists, where completing using a small key
-- takes a lot of time and will come up with meaningless results anyway (ie, a
-- too large dataset).
--
entryCompletionSetMinimumKeyLength :: EntryCompletion
 -> Int             -- ^ @length@ - The minimum length of the key in order to
                    -- start completing.
 -> IO ()
entryCompletionSetMinimumKeyLength self length =
  {# call gtk_entry_completion_set_minimum_key_length #}
    self
    (fromIntegral length)

-- | Returns the minimum key length as set for @completion@.
--
entryCompletionGetMinimumKeyLength :: EntryCompletion
 -> IO Int          -- ^ returns The currently used minimum key length.
entryCompletionGetMinimumKeyLength self =
  liftM fromIntegral $
  {# call gtk_entry_completion_get_minimum_key_length #}
    self

-- | Requests a completion operation, or in other words a refiltering of the
-- current list with completions, using the current key. The completion list
-- view will be updated accordingly.
--
entryCompletionComplete :: EntryCompletion -> IO ()
entryCompletionComplete self =
  {# call gtk_entry_completion_complete #}
    self

-- | Inserts an action in @completion@'s action item list at position @index@
-- with text @text@. If you want the action item to have markup, use
-- 'entryCompletionInsertActionMarkup'.
--
entryCompletionInsertActionText :: EntryCompletion
 -> Int             -- ^ @index@ - The index of the item to insert.
 -> String          -- ^ @text@ - Text of the item to insert.
 -> IO ()
entryCompletionInsertActionText self index text =
  withUTFString text $ \textPtr ->
  {# call gtk_entry_completion_insert_action_text #}
    self
    (fromIntegral index)
    textPtr

-- | Inserts an action in @completion@'s action item list at position @index@
-- with markup @markup@.
--
entryCompletionInsertActionMarkup :: EntryCompletion
 -> Int             -- ^ @index@ - The index of the item to insert.
 -> String          -- ^ @markup@ - Markup of the item to insert.
 -> IO ()
entryCompletionInsertActionMarkup self index markup =
  withUTFString markup $ \markupPtr ->
  {# call gtk_entry_completion_insert_action_markup #}
    self
    (fromIntegral index)
    markupPtr

-- | Deletes the action at @index@ from @completion@'s action list.
--
entryCompletionDeleteAction :: EntryCompletion
 -> Int             -- ^ @index@ - The index of the item to Delete.
 -> IO ()
entryCompletionDeleteAction self index =
  {# call gtk_entry_completion_delete_action #}
    self
    (fromIntegral index)

-- | Convenience function for setting up the most used case of this code: a
-- completion list with just strings. This function will set up @completion@ to
-- have a list displaying all (and just) strings in the completion list, and to
-- get those strings from @column@ in the model of @completion@.
--
-- This functions creates and adds a 'CellRendererText' for the selected
-- column.
--
entryCompletionSetTextColumn :: EntryCompletion
 -> Int             -- ^ @column@ - The column in the model of @completion@ to
                    -- get strings from.
 -> IO ()
entryCompletionSetTextColumn self column =
  {# call gtk_entry_completion_set_text_column #}
    self
    (fromIntegral column)

#if GTK_CHECK_VERSION(2,6,0)
-- | Requests a prefix insertion.
--
-- * Available since Gtk+ version 2.6
--
entryCompletionInsertPrefix :: EntryCompletion -> IO ()
entryCompletionInsertPrefix self =
  {# call gtk_entry_completion_insert_prefix #}
    self

-- | Returns the column in the model of the completion to get strings from.
--
-- * Available since Gtk+ version 2.6
--
entryCompletionGetTextColumn :: EntryCompletion
 -> IO Int          -- ^ returns the column containing the strings
entryCompletionGetTextColumn self =
  liftM fromIntegral $
  {# call gtk_entry_completion_get_text_column #}
    self

-- | Sets whether the common prefix of the possible completions should be
-- automatically inserted in the entry.
--
-- * Available since Gtk+ version 2.6
--
entryCompletionSetInlineCompletion :: EntryCompletion
 -> Bool            -- ^ @inlineCompletion@ - @True@ to do inline completion
 -> IO ()
entryCompletionSetInlineCompletion self inlineCompletion =
  {# call gtk_entry_completion_set_inline_completion #}
    self
    (fromBool inlineCompletion)

-- | Returns whether the common prefix of the possible completions should be
-- automatically inserted in the entry.
--
-- * Available since Gtk+ version 2.6
--
entryCompletionGetInlineCompletion :: EntryCompletion
 -> IO Bool         -- ^ returns @True@ if inline completion is turned on
entryCompletionGetInlineCompletion self =
  liftM toBool $
  {# call gtk_entry_completion_get_inline_completion #}
    self

-- | Sets whether the completions should be presented in a popup window.
--
-- * Available since Gtk+ version 2.6
--
entryCompletionSetPopupCompletion :: EntryCompletion
 -> Bool            -- ^ @popupCompletion@ - @True@ to do popup completion
 -> IO ()
entryCompletionSetPopupCompletion self popupCompletion =
  {# call gtk_entry_completion_set_popup_completion #}
    self
    (fromBool popupCompletion)

-- | Returns whether the completions should be presented in a popup window.
--
-- * Available since Gtk+ version 2.6
--
entryCompletionGetPopupCompletion :: EntryCompletion
 -> IO Bool         -- ^ returns @True@ if popup completion is turned on
entryCompletionGetPopupCompletion self =
  liftM toBool $
  {# call gtk_entry_completion_get_popup_completion #}
    self
#endif

--------------------
-- Properties

-- | Minimum length of the search key in order to look up matches.
--
-- Allowed values: >= 0
--
-- Default value: 1
--
entryCompletionMinimumKeyLength :: Attr EntryCompletion Int
entryCompletionMinimumKeyLength = Attr 
  entryCompletionGetMinimumKeyLength
  entryCompletionSetMinimumKeyLength

#if GTK_CHECK_VERSION(2,6,0)
-- | The column of the model containing the strings.
--
-- Allowed values: >= -1
--
-- Default value: -1
--
entryCompletionTextColumn :: Attr EntryCompletion Int
entryCompletionTextColumn = Attr 
  entryCompletionGetTextColumn
  entryCompletionSetTextColumn

-- | Determines whether the common prefix of the possible completions should
-- be inserted automatically in the entry.
--
-- Default value: @False@
--
entryCompletionInlineCompletion :: Attr EntryCompletion Bool
entryCompletionInlineCompletion = Attr 
  entryCompletionGetInlineCompletion
  entryCompletionSetInlineCompletion

-- | Determines whether the possible completions should be shown in a popup
-- window.
--
-- Default value: @True@
--
entryCompletionPopupCompletion :: Attr EntryCompletion Bool
entryCompletionPopupCompletion = Attr 
  entryCompletionGetPopupCompletion
  entryCompletionSetPopupCompletion
#endif

--------------------
-- Signals

#if GTK_CHECK_VERSION(2,6,0)
-- | Gets emitted when the inline autocompletion is triggered. The default
-- behaviour is to make the entry display the whole prefix and select the newly
-- inserted part.
--
-- Applications may connect to this signal in order to insert only a smaller
-- part of the @prefix@ into the entry - e.g. the entry used in the
-- 'FileChooser' inserts only the part of the prefix up to the next \'\/\'.
--
onInsertPrefix, afterInsertPrefix :: EntryCompletionClass self => self
 -> (String -> IO Bool)
 -> IO (ConnectId self)
onInsertPrefix = connect_STRING__BOOL "insert_prefix" False
afterInsertPrefix = connect_STRING__BOOL "insert_prefix" True
#endif

-- | Gets emitted when an action is activated.
--
onActionActivated, afterActionActivated :: EntryCompletionClass self => self
 -> (Int -> IO ())
 -> IO (ConnectId self)
onActionActivated = connect_INT__NONE "action_activated" False
afterActionActivated = connect_INT__NONE "action_activated" True
#endif
