module Codec.Beam.Internal where

import Control.Monad.State.Strict (State)
import Data.Map (Map)
import Data.Word (Word8, Word32)
import Data.ByteString.Lazy (ByteString)
import qualified Data.ByteString.Builder as BS


-- | You can find implementations in "Codec.Beam.Genop"
data Op
  = Op Word8 (State Builder [Operand])


data Operand
  = Lit Int
  | Int Int
  | Nil
  | Atom ByteString
  | Reg Register
  | Label Label
  | Ext Literal


data Literal
  = EInt Int
  | EFloat Double
  | EAtom ByteString
  | EBinary ByteString
  | ETuple [Literal]
  | EList [Literal]
  | EMap [(Literal, Literal)]


data Lambda
  = Lambda
      { _name :: ByteString
      , _arity :: Int
      , _label :: Int
      , _index :: Int
      , _free :: Int
      }


data Register
  = X Int
  | Y Int


type Label
  = Int


type Export
  = (ByteString, Int, Int)


data Access
  = Public
  | Private


data Builder =
  Builder
    { _moduleName :: Operand
    , _overallLabelCount :: Int
    , _currentLabelCount :: Int
    , _functionCount :: Word32
    , _atomTable :: Map ByteString Int
    , _literalTable :: [Literal]
    , _lambdaTable :: [Lambda]
    , _exportNextLabel :: Maybe (ByteString, Int)
    , _toExport :: [Export]
    , _code :: BS.Builder
    }