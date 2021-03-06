module Source.Lens where

open import Data.Maybe
open import Function
open import Level

record Applicative {ℓ} (F : Set ℓ → Set ℓ) : Set (suc ℓ) where
  infixl 4 _<*>_
  field
    _<*>_ : ∀ {A B} → F (A → B) → F A → F B
    pure : ∀{A} → A → F A

open Applicative{{...}} public

Identity-Applicative : Applicative {zero} id
Identity-Applicative = record { _<*>_ = id ; pure = id }

Maybe-Applicative : ∀{e} → Applicative {zero} (const (Maybe e))
Maybe-Applicative = record
  { _<*>_ = _<*>-maybe_
  ; pure = const nothing
  } where

    _<*>-maybe_ : ∀{e} → Maybe e → Maybe e → Maybe e
    nothing <*>-maybe nothing = nothing
    nothing <*>-maybe just x = just x
    just x <*>-maybe _ = just x

_<$>_
  : ∀ {ℓ} {F : Set ℓ → Set ℓ} {{app : Applicative {ℓ} F}}
  → ∀{A B} → (A → B) → F A → F B
f <$> a = pure f <*> a

Traversal : Set → Set → Set → Set → Set _
Traversal s s' a a' = {F : Set → Set} → {{app : Applicative F}} → (a → F a') → s → F s'

Traversal' : Set → Set → Set _
Traversal' s a = Traversal s s a a

view? : ∀{s a} → Traversal' s a → s → Maybe a
view? l = l {{Maybe-Applicative}} just

over : ∀{s s' a a'} → Traversal s s' a a' → (a → a') → (s → s')
over l = l {{Identity-Applicative}}
