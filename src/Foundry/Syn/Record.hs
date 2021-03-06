module Foundry.Syn.Record where

import Data.Kind (Type)
import Data.Foldable
import Control.Monad.Reader
import Control.Lens
import Data.Dynamic

import Data.Singletons.Prelude
import Data.Singletons.Prelude.List
import Data.Vinyl

import qualified Data.Singletons.TH as Sing
import qualified Language.Haskell.TH as TH

import Source.Syntax
import Source.Collage
import qualified Source.Input.KeyCode as KeyCode

import Foundry.Syn.Common

type family FieldTypes (sel :: Type) :: [Type]

newtype SynRecField k (sel :: k) = SynRecField (FieldTypes k :!! FromEnum sel)

deriving instance UndoEq (FieldTypes k :!! FromEnum sel) => UndoEq (SynRecField k sel)

makePrisms ''SynRecField

type SynRec sel =
  Rec (SynRecField sel) (EnumFromTo MinBound MaxBound)

data SynRecord sel = SynRecord
  { _synRec :: SynRec sel
  , _synRecSel :: Integer
  , _synRecSelSelf :: Bool
  }

makeLenses ''SynRecord

instance UndoEq (SynRec sel) => UndoEq (SynRecord sel) where
  undoEq a1 a2 = undoEq (a1 ^. synRec) (a2 ^. synRec)

synField
  :: ((r :: sel) ∈ EnumFromTo MinBound MaxBound)
  => Sing r
  -> Lens' (SynRecord sel) (FieldTypes sel :!! FromEnum r)
synField s = synRec . rlens s . _SynRecField

-- Selection-related classes

selOrder :: (Enum s, Bounded s) => [s]
selOrder = [minBound .. maxBound]

lookupNext :: Eq s => [s] -> s -> Maybe s
lookupNext ss s = lookup s (ss `zip` tail ss)

selRevOrder :: (Enum s, Bounded s) => [s]
selRevOrder = reverse selOrder

selNext, selPrev :: (Enum s, Bounded s, Eq s) => s -> Maybe s
selNext = lookupNext selOrder
selPrev = lookupNext selRevOrder

class SelLayout s where
  selLayoutHook :: s -> Op1 (CollageDraw' Int)

handleArrowUp :: SynSelection syn sel => React n rp la syn
handleArrowUp = do
  guardInputEvent $ keyCodeLetter KeyCode.ArrowUp 'k'
  False <- use synSelectionSelf
  synSelectionSelf .= True

handleArrowDown :: SynSelection syn sel => React n rp la syn
handleArrowDown = do
  guardInputEvent $ keyCodeLetter KeyCode.ArrowDown 'j'
  True <- use synSelectionSelf
  synSelectionSelf .= False

handleArrowLeft
  :: (SynSelection syn sel, Enum sel, Bounded sel, Eq sel)
  => React n rp la syn
handleArrowLeft = do
  guardInputEvent $ keyCodeLetter KeyCode.ArrowLeft 'h'
  False <- use synSelectionSelf
  selection <- use synSelection
  selection' <- maybeA (selPrev selection)
  synSelection .= selection'

handleArrowRight
  :: (SynSelection syn sel, Enum sel, Bounded sel, Eq sel)
  => React n rp la syn
handleArrowRight = do
  guardInputEvent $ keyCodeLetter KeyCode.ArrowRight 'l'
  False <- use synSelectionSelf
  selection <- use synSelection
  selection' <- maybeA (selNext selection)
  synSelection .= selection'

handleArrows
  :: (SynSelection syn sel, Enum sel, Bounded sel, Eq sel)
  => React n rp la syn
handleArrows = asum
  [handleArrowUp, handleArrowDown, handleArrowLeft, handleArrowRight]

instance (SingKind sel, Demote sel ~ sel, Enum sel)
      => SynSelfSelected (SynRecord sel)

instance (SingKind sel, Demote sel ~ sel, Enum sel)
      => SynSelection (SynRecord sel) sel where
  synSelection = synRecSel . iso (toEnum . fromIntegral) (toInteger . fromEnum)
  synSelectionSelf = synRecSelSelf

recHandleSelRedirect :: TH.Name -> TH.ExpQ
recHandleSelRedirect selTypeName =
  [e| do False <- use synSelectionSelf
         SomeSing selection <- uses synRecSel (toSing . toEnum . fromIntegral)
         $(Sing.sCases selTypeName [e|selection|]
             [e|reactRedirect (synField selection)|])
   |]

selLayout ::
  forall t (a :: t).
     (Demote t ~ t, SelLayout t, Enum t,
      (a ∈ EnumFromTo MinBound MaxBound),
      SingKind t, SyntaxLayout Int ActiveZone LayoutCtx (FieldTypes t :!! FromEnum a),
      SynSelfSelected (FieldTypes t :!! FromEnum a), Typeable t, Eq t)
  => Sing a
  -> SynRecord t
  -> Reader LayoutCtx (CollageDraw' Int)
selLayout ssel syn = do
  let
    sel' = fromSing ssel
    sub = view (synField ssel) syn
    appendSelection
      = (lctxSelected &&~ (view synSelection syn == sel'))
      . (lctxSelected &&~ (synSelfSelected syn == False))
      . (lctxPath %~ (`snoc` toDyn sel'))
    enforceSelfSelection
      = lctxSelected &&~ synSelfSelected sub
  local appendSelection $ do
    a <- layout sub
    reader $ \lctx ->
       sel (enforceSelfSelection lctx)
     $ selLayoutHook sel' a
