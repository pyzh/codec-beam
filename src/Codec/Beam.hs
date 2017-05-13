module Codec.Beam
  ( Builder, encode
  , Instruction, Atom, Label, Tagged(..), Register(..)
  , atom, label, export, funcInfo, intCodeEnd, ret, move
  ) where

import qualified Control.Monad.State as State

import Data.Binary.Put (runPut, putWord32be)
import Data.Bits (shiftL, (.|.))
import Data.ByteString.Lazy (ByteString)
import Data.Map ((!))
import Data.Monoid ((<>))
import Data.Word (Word8, Word32)
import qualified Data.ByteString.Lazy as BS
import qualified Data.List as List
import qualified Data.Map as Map


{-| Create structurally correct BEAM code.
 -}


type Builder a
  = State.State Env a


data Env
  = Env
      { moduleName :: ByteString
      , labelCount :: Word32
      , functionCount :: Word32
      , atomTable :: Map.Map ByteString Int
      , toExport :: [(ByteString, Int, Label)]
      }


newtype Instruction
  = Instruction (Word32, [Tagged])


encode :: ByteString -> Builder [Instruction] -> ByteString
encode name builder =
  let
    (instructions, env) =
      State.runState builder $ Env
        { moduleName = name
        , labelCount = 1
        , functionCount = 0
        , atomTable = Map.singleton name 1
        , toExport = []
        }

    sections =
      mconcat
        [ "Atom" <> alignSection (encodeAtoms env)
        , "Code" <> alignSection (encodeCode env instructions)
        , "LocT" <> alignSection (pack32 0)
        , "StrT" <> alignSection (pack32 0)
        , "ImpT" <> alignSection (pack32 0)
        , "ExpT" <> alignSection (encodeExports env)
        ]
  in
    "FOR1" <> pack32 (BS.length sections + 4) <> "BEAM" <> sections


encodeAtoms :: Env -> ByteString
encodeAtoms env =
  pack32 (length list) <> concatM fromName list

  where
    fromName name =
      pack8 (BS.length name) <> name

    list =
      map fst
        $ List.sortOn snd
        $ Map.toList (atomTable env)


encodeCode :: Env -> [Instruction] -> ByteString
encodeCode env instructions =
  let
    headerLength =
      16

    instructionSetId =
      0

    maxOpCode =
      158

    fromInstruction (Instruction (opCode, args)) =
      pack8 opCode <> BS.pack (concatM (fromTagged env) args)
  in
    mconcat
      [ pack32 headerLength
      , pack32 instructionSetId
      , pack32 maxOpCode
      , pack32 (labelCount env)
      , pack32 (functionCount env)
      , concatM fromInstruction instructions
      ]


encodeExports :: Env  -> ByteString
encodeExports env =
  let
    list =
      toExport env

    fromExport (name, arity, L lid) =
      pack32 (atomTable env ! name) <> pack32 arity <> pack32 lid
  in
    pack32 (length list) <> concatM fromExport list



-- TERMS


newtype Atom
  = A ByteString
  deriving (Eq, Ord)


atom :: ByteString -> Builder Atom
atom name =
  do  State.modify $
        \env -> env { atomTable = check (atomTable env) }

      return (A name)

  where
    check old =
      if Map.member name old then
        old

      else
        Map.insert name (Map.size old + 1) old


newtype Label
  = L Word32


label :: Builder (Label, Instruction)
label =
  do  next <-
        State.gets labelCount

      let id =
            L next

      State.modify $
        \env -> env { labelCount = next + 1 }

      return ( id, op 1 [ Literal (fromIntegral next) ] )



-- OPS


data Register
  = X Int
  | Y Int


data Tagged
  = Literal Int
  | Integer Int
  | Atom Atom
  | Reg Register
  | Label Label


op :: Word32 -> [Tagged] -> Instruction
op code args =
  Instruction (code, args)


export :: ByteString -> Int -> Label -> Builder Instruction
export name arity location =
  do  State.modify $
        \env -> env { toExport = (name, arity, location) : toExport env }

      funcInfo name arity


funcInfo :: ByteString -> Int -> Builder Instruction
funcInfo name a =
  do  State.modify $
        \env -> env { functionCount = functionCount env + 1 }

      m <- atom =<< State.gets moduleName
      f <- atom name

      return $ op 2 [ Atom m, Atom f, Literal a ]


intCodeEnd :: Instruction
intCodeEnd =
  op 3 []


ret :: Instruction
ret =
  op 19 []


move :: Tagged -> Register -> Instruction
move source destination =
  op 64 [ source, Reg destination ]



-- BYTES


fromTagged :: Env -> Tagged -> [Word8]
fromTagged env t =
  case t of
    Literal value ->
      compact 0 value

    Integer value ->
      compact 1 value

    Atom (A name) ->
      compact 2 (atomTable env ! name)

    Reg (X id) ->
      compact 3 id

    Reg (Y id) ->
      compact 4 id

    Label (L id) ->
      compact 5 id


compact :: Integral n => Word8 -> n -> [Word8]
compact tag n =
  if n < 16 then
    [ shiftL (fromIntegral n) 4 .|. tag ]

  else
    error "TODO"


alignSection :: ByteString -> ByteString
alignSection bytes =
  pack32 size <> bytes <> padding

  where
    size =
      BS.length bytes

    padding =
      case mod size 4 of
        0 -> BS.empty
        r -> BS.replicate (4 - r) 0


pack8 :: Integral n => n -> ByteString
pack8 =
  BS.singleton . fromIntegral


pack32 :: Integral n => n -> ByteString
pack32 n =
  runPut (putWord32be (fromIntegral n :: Word32))



-- HELPERS


concatM :: Monoid m => (a -> m) -> [a] -> m
concatM f =
  mconcat . map f
