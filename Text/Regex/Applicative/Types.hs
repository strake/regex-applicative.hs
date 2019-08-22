{-# LANGUAGE GADTs #-}
module Text.Regex.Applicative.Types where

import Control.Applicative
import Data.String

newtype ThreadId = ThreadId Int

-- | A thread either is a result or corresponds to a symbol in the regular
-- expression, which is expected by that thread.
data Thread s r
    = Thread
        { threadId_ :: ThreadId
        , _threadCont :: s -> [Thread s r]
        }
    | Accept r

-- | Returns thread identifier. This will be 'Just' for ordinary threads and
-- 'Nothing' for results.
threadId :: Thread s r -> Maybe ThreadId
threadId Thread { threadId_ = i } = Just i
threadId _ = Nothing

data Greediness = Greedy | NonGreedy
    deriving (Show, Read, Eq, Ord, Enum)

-- | Type of regular expressions that recognize symbols of type @s@ and
-- produce a result of type @a@.
--
-- Regular expressions can be built using 'Functor', 'Applicative' and
-- 'Alternative' instances in the following natural way:
--
-- * @f@ '<$>' @ra@ matches iff @ra@ matches, and its return value is the result
-- of applying @f@ to the return value of @ra@.
--
-- * 'pure' @x@ matches the empty string (i.e. it does not consume any symbols),
-- and its return value is @x@
--
-- * @rf@ '<*>' @ra@ matches a string iff it is a concatenation of two
-- strings: one matched by @rf@ and the other matched by @ra@. The return value
-- is @f a@, where @f@ and @a@ are the return values of @rf@ and @ra@
-- respectively.
--
-- * @ra@ '<|>' @rb@ matches a string which is accepted by either @ra@ or @rb@.
-- It is left-biased, so if both can match, the result of @ra@ is used.
--
-- * 'empty' is a regular expression which does not match any string.
--
-- * 'many' @ra@ matches concatenation of zero or more strings matched by @ra@
-- and returns the list of @ra@'s return values on those strings.
--
-- * 'some' @ra@ matches concatenation of one or more strings matched by @ra@
-- and returns the list of @ra@'s return values on those strings.
data RE s a where
    Eps :: RE s ()
    Symbol :: ThreadId -> (s -> Maybe a) -> RE s a
    Alt :: RE s a -> RE s a -> RE s a
    App :: RE s (a -> b) -> RE s a -> RE s b
    Fmap :: (a -> b) -> RE s a -> RE s b
    Fail :: RE s a
    Rep :: Greediness    -- repetition may be greedy or not
        -> (b -> a -> b) -- folding function (like in foldl)
        -> b             -- the value for zero matches, and also the initial value
                         -- for the folding function
        -> RE s a
        -> RE s b
    Void :: RE s a -> RE s ()

instance Functor (RE s) where
    fmap f x = Fmap f x
    f <$ x = pure f <* x

instance Applicative (RE s) where
    pure x = const x <$> Eps
    a1 <*> a2 = App a1 a2
    a *> b = pure (const id) <*> Void a <*> b
    a <* b = pure const <*> a <*> Void b

instance Alternative (RE s) where
    a1 <|> a2 = Alt a1 a2
    empty = Fail
    many a = reverse <$> Rep Greedy (flip (:)) [] a
    some a = (:) <$> a <*> many a

instance (char ~ Char, string ~ String) => IsString (RE char string) where
    fromString = string

-- | Match and return the given sequence of symbols.
--
-- Note that there is an 'IsString' instance for regular expression, so
-- if you enable the @OverloadedStrings@ language extension, you can write
-- @string \"foo\"@ simply as @\"foo\"@.
--
-- Example:
--
-- >{-# LANGUAGE OverloadedStrings #-}
-- >import Text.Regex.Applicative
-- >
-- >number = "one" *> pure 1  <|>  "two" *> pure 2
-- >
-- >main = print $ "two" =~ number
string :: Eq a => [a] -> RE a [a]
string = traverse sym

-- | Match and return a single symbol which satisfies the predicate
psym :: (s -> Bool) -> RE s s
psym p = msym (\s -> if p s then Just s else Nothing)

-- | Like 'psym', but allows to return a computed value instead of the
-- original symbol
msym :: (s -> Maybe a) -> RE s a
msym p = Symbol (error "Not numbered symbol") p

-- | Match and return the given symbol
sym :: Eq s => s -> RE s s
sym s = psym (s ==)
