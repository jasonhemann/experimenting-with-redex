#lang scribble/manual
@(require "lib.rkt" (except-in "syntax.scrbl" doc) (except-in "eval.scrbl" doc))

@title[#:tag "sec:judgment"]{Judgments in Redex}
The final piece of my model will be the judgments.
Judgments encode all the properties I care about for my expressions and
evaluation function.
These include judgments like program equivalence and well typedness.
Redex gives me the same inference rule notation I use on paper, and a spectrum
of automagic computability for judgments.

After defining a judgment, Redex can:
@itemize[
@item{decide whether a moded judgment holds}
@item{compute the output positions of a moded judgment holds}
@item{decide whether a derivation for a modeless judgment is valid}
@item{build derivations of a moded judgment for you}
@item{generate terms satisfying a judgment}
]

@margin-note{Redex uses the American spelling of @emph{judgment}.}

@section{Judgment TLDR}
I define judgments using @racket[define-judgment-form].
This form allows me to specify the judgment in a relation presentation, and use
all of Redex's pattern language in the process.
Once I define a judgment, I can query whether the judgment holds, and even
generate terms that satisfy the judgment.

If I @racket[#:mode] and give output positions in the judgment, Redex will
automatically compute the terms in output position from the terms I provide in
input positions.
I use @racket[judgment-holds] to ask Redex whether a judgment holds, and to
compute the output of judgments.
I use @racket[build-derivations] to have Redex automatically build derivations
for moded judgments.
For modeless judgments, I can manually build derivations using
@racket[derivation] and ask whether the derivation is valid using
@racket[judgment-holds].
This can be extremely useful for teaching, checking intuition, and debugging
judgments.

For testing, I can use @racket[test-judgment-holds] to test a judgment.
Usually, I want to test meta-theoretic properties of judgments by using
@racket[redex-check].

A common pitfall is to use the wrong language name when defining a judgment.
The result is the judgment silently failing to hold, even when you think it
ought to.
This causes me to avoid using @racket[define-extended-language] as much as
possible to reduce the number of language names I need to keep track of.

There are two important caveats to keep in mind while using judgments.
First, they can be frustrating to debug, since Redex only gives you a boolean
value: whether the judgment holds or not.
I normally resort to @racket[printf] debugging.
The recent addition of modeless judgments provides a new avenue for debugging
that seems promising, although I haven't used this approach in practice.
Second, ellipses and Racket escapes are a double-edged sword.
While they make defining judgments much easier, they also prevent Redex from
generating terms that satisfy the judgment.

@section{βη-equality Judgment}
The first judgment I usually define is an equivalence judgment for expressions.
I will usually extend the normalization relation to an
equivalence relation, sometimes including η-equivalence.

Below, I define βη-equivalence for @tech{BoxyL}.

@examples[
#:eval boxy-evalor
(define-judgment-form BoxyL
  #:contract (≡ e e)
  #:mode (≡ I I)

  [(where (e e) ((normalize e_1) (normalize e_2)))
   ----------- "β"
   (≡ e_1 e_2)]

  [(≡ e_1 (e_2 x))
   --------------- "η₁"
   (≡ (λ (x : A) e_1) e_2)]

  [(≡ (e_2 x) e_1)
   ------------------------ "η₂"
   (≡ e_2 (λ (x : A) e_1))])
]

The form @racket[define-judgment-form] takes a language identifier and a
sequence of rules, written in the traditional inference rule notation.
The horizontal line can be followed by an optional name for the rule.
The length of the horizontal line must be greater than 2 hyphens.

The judgment definition also takes an optional contract declaration and optional
mode declaration.
I also use a contract to help catch bugs, including some syntax pitfalls
mentioned earlier.
The mode lines requires either @racket[I] for an input or @racket[O] for an
output position.
The more output positions you have, the more Redex can compute for you, but the
more algorithmic you must make your rules.

You can use the full Redex pattern language in any input and the Redex term
language, including metafunctions, in any output.
(Recall that input and output flips in premises; inputs become term positions
and outputs become pattern positions.)
You can use any other judgment directly as a premise.
For non-judgment side-conditions, I frequently use @rtech{where clauses} and use
@rtech{side-condition} sparingly.
Note that @rtech{side-conditions} in judgment forms are Redex terms, and
@racket[unquote] to use Racket expressions.
This is unlike @rtech{side-conditions} in grammar, which are Racket expressions and
must quote using @racket[term] to use Redex terms.

We use the Racket function @racket[judgment-holds] to ask whether a well-moded
judgment holds for particular inputs.
Redex will search through the judgment rules, and return either @racket[#t] or
@racket[#f]

@examples[
#:eval boxy-evalor
(judgment-holds
 (≡ (λ (x : Nat) ((λ (x : Nat) x) 5))
    (λ (x : Nat) 5)))

(judgment-holds
 (≡ (f 5)
    (λ (x : Nat) ((f 5) x))))
]

Judgments which are exclusively in input mode can be used as metafunctions.
I never do this, because (1) I rarely have input-only judgments and (2) typos can
easily lead to the symbols-interpreted-as-variables problem, but
@racket[judgment-holds] will report some errors when given bad inputs.

@examples[
#:eval boxy-evalor
(term
 (≡ (f 5)
    (λ (x : Nat) ((f 5) x))))

(term
 (= (f 5)
    (λ (x : Nat) ((f 5) x))))

(eval:error
 (judgment-holds
  (= (f 5)
     (λ (x : Nat) ((f 5) x)))))
]

@section{Typing Judgment}
The next judgments I define are the typing judgments.
This usually requires an extension to the language to define environments,
syntactically.

@examples[
#:eval boxy-evalor
(define-extended-language BoxyTypingL BoxyL
  (Γ Δ ::= · (Γ (x : A))))
]

I usually write my environments as snoc-lists, as we do on paper.
Shadowing is structural, as on paper; I don't need to worry about freshness or
anything, since Redex "Does The Right Thing™" when deconstructing a binder
and putting it in the context.

To define the type system, I usually give a well-moded algorithmic presentation
that computes the type from the environment and the term.
This means I usually need my syntax to be full annotated; conveniently, that is
already the case.
Sometimes I need to go back and modify my syntax with some extra annotations.

Below is the type system for @tech{BoxyL}.
I first define a helper for distinguishing variables.
Redex has a special pattern for non-matching patterns, called bang pattern, but
frankly they're hard to use and read.

@examples[
#:eval boxy-evalor
(define-metafunction BoxyTypingL
  different : x x -> boolean
  [(different x x) #f]
  [(different x y) #t])

(define-judgment-form BoxyTypingL
  #:contract (type-infer Δ Γ e A)
  #:mode (type-infer I I I O)

  [------------------------------- "T-VarLocal"
   (type-infer Δ (Γ (x : A)) x A)]

  [(type-infer Δ Γ x_1 A)
   (where #t (different x_1 x_2))
   ------------------------------- "T-VarLocalWeak"
   (type-infer Δ (Γ (x_2 : B)) x_1 A)]

  [------------------------------- "T-VarGlobal"
   (type-infer (Δ (x : A)) · x A)]

  [(type-infer Δ · x_1 A)
   ----------------------------------- "T-VarGlobalWeak"
   (type-infer (Δ (x_2 : B)) · x_1 A)]

  [-------------------------- "T-Nat"
   (type-infer Δ Γ natural Nat)]

  [(type-infer Δ Γ e_1 Nat)
   (type-infer Δ Γ e_2 Nat)
   -------------------------- "T-Plus"
   (type-infer Δ Γ (+ e_1 e_2) Nat)]

  [(type-infer Δ Γ e_1 A)
   (type-infer Δ Γ e_2 B)
   -------------------------- "T-Cons"
   (type-infer Δ Γ (cons e_1 e_2) (A × B))]

  [(type-infer Δ Γ e (A × B))
   -------------------------- "T-Car"
   (type-infer Δ Γ (car e) A)]

  [(type-infer Δ Γ e (A × B))
   -------------------------- "T-Cdr"
   (type-infer Δ Γ (cdr e) B)]

  [(type-infer Δ (Γ (x : A)) e B)
   -------------------------- "T-Fun"
   (type-infer Δ Γ (λ (x : A) e) (A → B))]

  [(type-infer Δ Γ e_1 (A → B))
   (type-infer Δ Γ e_2 A)
   -------------------------- "T-App"
   (type-infer Δ Γ (e_1 e_2) B)]

  [(type-infer Δ · e A)
   -------------------------- "T-Box"
   (type-infer Δ Γ (box e) (□ A))]

  [(type-infer Δ Γ e_1 (□ A))
   (type-infer (Δ (x : A)) Γ e_2 B)
   -------------------------- "T-LetBox"
   (type-infer Δ Γ (let ((box x) e_1) e_2) B)])
]

@;I usually define separate check and infer judgments.
@;In this case, I only include @racket[type-check] and @racket[type-equal] to show
@;the general structure I use.
@;In BoxyL, the check judgment is trivial because there is no type-level
@;computation or subtyping.

Once I have a type system, I can ask Redex to infer the types of expressions.

@examples[
#:eval boxy-evalor
(judgment-holds (type-infer · · (box 1) A) (term A))
(judgment-holds (type-infer · · (λ (x : Nat) (box 1)) A) (term A))
(judgment-holds (type-infer · (· (x : Nat)) (box x) A) (term A))
(judgment-holds (type-infer · (· (x : Nat)) (box x) A))
]

Redex will either return the set of valid types, including the empty set if I
asked for an output, or @racket[#f] if the judgment doesn't hold and I did not
ask for any output.

You can also ask Redex for the entire derivation, rather than just a "yes" or "no".

@examples[
#:eval boxy-evalor
(build-derivations (type-infer · · (box 1) A))
(build-derivations (type-infer · (· (x : Nat)) (box x) A))
]

@racket[build-derivations] will return the set of valid derivations.

For modeless judgments, I can manually build a derivation and use
@racket[judgment-holds] to check that the derivation is valid.
Note that this @emph{only} works for modeless judgments; I show a simple
workaround to do this for moded judgments shortly.
@margin-note{This might change soon, as it seems like a simple and useful change
to check a derivation against a moded judgment.}
In the example below, I define a modeless version of @racket[type-infer] that is
identical but with the @racket[#:mode] line removed.
@examples[
#:eval boxy-evalor
(eval:alts
(define-judgment-form BoxyTypingL
  #:contract (type Δ Γ e A)

  [------------------------------- "T-VarLocal"
   (type Δ (Γ (x : A)) x A)]

  [(type Δ Γ x_1 A)
   (where #t (different x_1 x_2))
   ------------------------------- "T-VarLocalWeak"
   (type Δ (Γ (x_2 : B)) x_1 A)]

  ...

  [(type Δ · e A)
   -------------------------- "T-Box"
   (type Δ Γ (box e) (□ A))])
 (define-judgment-form BoxyTypingL
  #:contract (type Δ Γ e A)

  [------------------------------- "T-VarLocal"
   (type Δ (Γ (x : A)) x A)]

  [(type Δ Γ x_1 A)
   (where #t (different x_1 x_2))
   ------------------------------- "T-VarLocalWeak"
   (type Δ (Γ (x_2 : B)) x_1 A)]

  [------------------------------- "T-VarGlobal"
   (type (Δ (x : A)) · x A)]

  [(type Δ · x_1 A)
   ----------------------------------- "T-VarGlobalWeak"
   (type (Δ (x_2 : B)) · x_1 A)]

  [-------------------------- "T-Nat"
   (type Δ Γ natural Nat)]

  [(type Δ Γ e_1 Nat)
   (type Δ Γ e_2 Nat)
   -------------------------- "T-Plus"
   (type Δ Γ (+ e_1 e_2) Nat)]

  [(type Δ Γ e_1 A)
   (type Δ Γ e_2 B)
   -------------------------- "T-Cons"
   (type Δ Γ (cons e_1 e_2) (A × B))]

  [(type Δ Γ e (A × B))
   -------------------------- "T-Car"
   (type Δ Γ (car e) A)]

  [(type Δ Γ e (A × B))
   -------------------------- "T-Cdr"
   (type Δ Γ (cdr e) B)]

  [(type Δ (Γ (x : A)) e B)
   -------------------------- "T-Fun"
   (type Δ Γ (λ (x : A) e) (→ A B))]

  [(type Δ Γ e_1 (A → B))
   (type Δ Γ e_2 A)
   -------------------------- "T-App"
   (type Δ Γ (e_1 e_2) B)]

  [(type Δ · e A)
   -------------------------- "T-Box"
   (type Δ Γ (box e) (□ A))]

  [(type Δ Γ e_1 (□ A))
   (type (Δ (x : A)) Γ e_2 B)
   -------------------------- "T-LetBox"
   (type Δ Γ (let ((box x) e_1) e_2) B)]))

(judgment-holds
 type
 (derivation
  `(type · (· (x : Nat)) x Nat)
  "T-VarLocal"
  (list)))
(judgment-holds type
 (derivation
 `(type · (· (x : Nat)) (box x) (□ Nat))
 "T-Box"
 (list
  (derivation
   `(type · (· (x : Nat)) x Nat)
   "T-VarLocal"
   (list)))))
(judgment-holds
 type
 (derivation
  `(type (· (x : Nat)) · (box x) (□ Nat))
  "T-Box"
  (list
   (derivation
    `(type (· (x : Nat)) · x Nat)
    "T-VarGlobal"
    (list)))))
]

We can emulate the behavior for moded judgments, by comparing against the
set of derivations given by @racket[build-derivations].
@examples[
#:eval boxy-evalor
(require racket/set)
(set-member?
 (build-derivations (type-infer (· (x : Nat)) · (box x) (□ Nat)))
 (derivation
  `(type-infer (· (x : Nat)) · (box x) (□ Nat))
  "T-Box"
  (list
   (derivation
    `(type-infer (· (x : Nat)) · x Nat)
    "T-VarGlobal"
    (list)))))

(define (check-moded-derivation d)
  (set-member?
   (code:comment "Sometimes you just need an eval")
   (eval `(build-derivations ,(derivation-term d)))
   d))

(check-moded-derivation
 (derivation
  `(type-infer (· (x : Nat)) · (box x) (□ Nat))
  "T-Box"
  (list
   (derivation
    `(type-infer (· (x : Nat)) · x Nat)
    "T-VarGlobal"
    (list)))))
]

In more complex language models, I will define separate @racket[type-infer] and
@racket[type-check] judgments, plus a subtyping or type equivalence judgment.
I define the @racket[type-check] via a single rule that appeals to the
@racket[type-infer] judgment and subtyping or equivalence.
@examples[
#:eval boxy-evalor
(define-metafunction BoxyL
  type-equal? : A B -> boolean
  [(type-equal? A A) #t]
  [(type-equal? A B) #f])

(define-judgment-form BoxyTypingL
  #:contract (type-check Δ Γ e A)
  #:mode (type-check I I I I)

  [(type-infer Δ Γ e A)
   (where #t (type-equal? A B))
   --------------------
   (type-check Δ Γ e B)])

(judgment-holds (type-check · · (box 5) (□ Nat)))
]

@section{Testing Judgments}
After we move to testing judgments, we can use @racket[test-judgment-holds].
@examples[
#:eval boxy-evalor
(test-judgment-holds (type-check · · (box 5) (□ Nat)))
(test-judgment-holds type (derivation
                           `(type · · (box 5) (□ Nat))
                           "T-Box"
                           (list
                            (derivation
                             `(type · · 5 Nat)
                             "T-Nat"
                             (list)))))
(test-judgment-holds type (derivation
                           `(type · · (box 5) (□ Nat))
                           "T-Box"
                           (list)))
(test-results)
]

@racket[test-judgment-holds] has two different interfaces: one for moded
judgments, and one for modeless judgments.

Unfortunately, there is no built-in way to check judgments for moded judgments.
Thankfully, we can quickly create @racket[test-derivation].

@examples[
#:eval boxy-evalor
(require (for-syntax racket/base syntax/parse))
(define (check-modeless-derivation d)
  (eval `(judgment-holds ,(car (derivation-term d)) ,d)))
(require racket/pretty)
(define (test-derivation f d)
  (define (raise-derivation-error d)
    (error
     'test-derivation
     "invalid (sub)derivation~n  judgment:~n    ~a~n  derivation:~n    ~a"
     (pretty-format (derivation-term d)) (pretty-format d)))
  (let ([ls (derivation-subs d)])
    (if (null? ls)
        (f d)
        (begin
          (for ([d ls])
            (unless (test-derivation f d)
              (raise-derivation-error d)))
          (unless (f d)
            (raise-derivation-error d))))))

(define proof
  (derivation
   `(type-infer · · (+ 5 (cons 5 1)) Nat)
   "Plus"
   (list
    (derivation `(type-infer · · 5 Nat) "T-Nat"  '())
    (derivation `(type-infer · · (cons 5 1) Nat) "T-Car" '()))))

(check-moded-derivation proof)

(eval:error (test-derivation check-moded-derivation proof))
code:blank
(eval:error (test-derivation
             check-modeless-derivation
             (derivation
              `(type · · (+ 5 (car (cons 5 1))) Nat)
              "Plus"
              (list
               (derivation `(type · · 5 Nat) "Nat"  '())
               (derivation `(type · · (car (cons 5 1)) Nat) "Nat" '())))))
(eval:error (test-derivation
             check-modeless-derivation
             (derivation
              `(type · · (+ 5 (car (cons 5 1))) Nat)
              "T-Plus"
              (list
               (derivation `(type · · 5 Nat) "T-Nat"  '())
               (derivation `(type · · (car (cons 5 1)) Nat) "T-Nat" '())))))

]
@margin-note{@racket[test-derivation] may get merged in to Redex soon, if I can
integrate it with the Redex test infrastructure.}

@section{Meta-theory Random-testing}
After I have some judgments, I can start generating terms from judgments.
For example, we can generate well-typed terms.
@examples[
#:eval boxy-evalor
(eval:alts
 (generate-term BoxyTypingL #:satisfying (type-infer Δ Γ e A) 3)
 '(type-infer ((· (z : Nat)) (H : Nat)) ((· (J : Nat)) (E : Nat)) 1 Nat))
(eval:alts
 (generate-term BoxyTypingL #:satisfying (type-infer Δ Γ e A) 10)
 '(type-infer · · 1 Nat))
]
This can let me do random-testing of meta-theoretic properties.
@;
@; TODO Bug in Redex
@;In BoxyL, one simple property that ought to hold is that all well-typed values
@;of type @redex{(□ A)} ought to be well-typed in the empty local environment.
@;@examples[
@;#:eval boxy-evalor
@;(redex-check
@; BoxyTypingL
@; #:satisfying (type-infer Δ Γ v (□ A))
@; (judgment-holds (type-infer Δ · v (□ A)))
@; #:attempts 1000)
@;]
@;
For example, we might check type safety: all closed well-typed expression
evaluate to values.
@examples[
#:eval boxy-evalor
(redex-check
 BoxyTypingL
 #:satisfying (type-infer · · e A)
 (redex-match? BoxyEvalL v (term (boxy-eval e)))
 #:attempts 1000)
]

Redex will report how many successful attempts it made, and how many failed
generations.
Redex can fail to find a good derivation a lot of the time, due annoying
internal details.
This usually doesn't indicate a problem, and you should just increase the number
of attempts.
You can also use @racket[#:prepare] to try to fix up generated examples.

@section{Pitfall: Using the Wrong Language Name}
While using @racket[define-extended-language] is nice for modularizing syntax
and for pedagogical presentations, I rarely use it in practice.
It's very easy to use the wrong language identifier when defining judgments, and
the result can be quite mysterious errors.
The errors are easier to spot when you use contracts---typically, some
nonterminal in the contract will be undefined, so the judgment will report a
useful error message.

@examples[
#:eval boxy-evalor
(define-judgment-form BoxyL
  #:contract (type-wrong Δ Γ e A)
  #:mode (type-wrong I I I I)

  [-------------- "Dummy Rule"
   (type-wrong Δ Γ e A)])

(eval:error (judgment-holds (type-wrong · · 5 Nat)))
]

If you don't use the nonterminal in a contract, then the judgment will just
assume you meant that nonterminal as a symbol, and silently fail to hold.

@examples[
#:eval boxy-evalor
(define-judgment-form BoxyL
  #:mode (type-wrong^ I I I I)

  [-------------- "Dummy Rule"
   (type-wrong^ Δ Γ e A)])

(judgment-holds (type-wrong^ · · 5 Nat))
]

@section{Caveat: Debugging Judgments}
When a judgment doesn't hold, Redex does not give you any help.
It merely fails and returns @racket[#f] or @racket['()].
When it appears that a judgment ought to hold, this can be extremely frustrating
to debug.

We can use the @gtech{parameter} @racket[current-traced-metafunctions] to ask Redex's to
print its trace of the search through the judgment.
This is essentially a fancy version of printf debugging, but works well for
small derivations.

@examples[
#:eval boxy-evalor
(define-judgment-form BoxyTypingL
  #:mode (type-debug I I I O)

  [-------------- "Nat"
   (type-debug Δ Γ natural Nat)]

  [(type-debug Δ Γ e_1 Nat)
   (type-debug Δ Γ e_2 Nat)
   -------------- "Plus"
   (type-debug Δ Γ (+ e_1 e_2) Nat)])

(parameterize ([current-traced-metafunctions '(type-debug)])
  (judgment-holds (type-debug · · (+ 5 (car (cons 5 1))) Nat)))
]

Now we know that the sub-derivation that failed is in the premise for
@racket[+] with the sub-expressions @racket[(car (cons 5 1))].

For large judgments and derivations, this method does not work well.
Instead, you may want to only observe certain rules.
The best method I've found for doing this is inserting @racket[printf]s as
@rtech{side-conditions}.

@examples[
#:eval boxy-evalor
(define-judgment-form BoxyTypingL
  #:mode (type-debug^ I I I O)

  [-------------- "Nat"
   (type-debug^ Δ Γ natural Nat)]

  [(type-debug^ Δ Γ e_1 Nat)
   (side-condition ,(printf "Plus premise one held for ~a~n" (term e_1)))
   (type-debug^ Δ Γ e_2 Nat)
   (side-condition ,(printf "Plus premise two held for ~a~n" (term e_2)))
   -------------- "Plus"
   (type-debug^ Δ Γ (+ e_1 e_2) Nat)])

(judgment-holds (type-debug^ · · (+ 5 (car (cons 5 1))) Nat))
]

Recall that @rtech{side-conditions} in judgment forms must unquote to use Racket
expressions.

@section{Caveat: Ellipses and Racket Escapes}
The Redex pattern language supports ellipses matching on sequences of patterns.
This is extremely convenient and matches common on-paper vector notation.
Unfortunately, it also completely defeats Redex term generation, so you cannot
use that judgment to generate derivations (and thus, @emph{e.g.}, generate
well-typed terms).
This is a severe and unfortunate limitation.

My usual solution is to avoid any ellipses in my syntax, and instead rely on
nesting and currying.
This reduces the need for ellipses in judgments.
It is easy to define additional metafunctions to provide nicer surface syntax
and still get good term generation.
For example, we can define n-ary surface syntax for @racket[BoxyL] as below, and
still have good well-typed term generation.

@examples[
#:eval boxy-evalor
(define-metafunction BoxyL
  λ* : (x : A) ... e -> e
  [(λ* (x : A) e)
   (λ (x : A) e)]
  [(λ* (x : A) any_1 ... e)
   (λ (x : A) (λ* any_1 ... e))])

(define-metafunction BoxyL
  app : e ... -> e
  [(app e_1)
   e_1]
  [(app e_1 e_2 any ...)
   (app (e_1 e_2) any ...)])

(redex-match? BoxyL e (term (λ* (x : Nat) (y : Nat) x)))
(redex-match? BoxyL e (term (app (λ* (x : Nat) (y : Nat) x) 5 6)))
(term (boxy-eval (app (λ* (x : Nat) (y : Nat) x) 5 6)))
]

Other features also defeat derivation generation, notably escaping into Racket.
This one can be harder to fix.
If we're only escaping to Racket for natual number or booleans, we can encode
the computation as an inductive data type in Redex.

When I cannot avoid ellipses or escaping, I will make due with generating terms
from grammars and try to fix them up, for example, by initializing mutual
variables or by replacing ill-typed subexpressions with obviously well-typed ones.
This doesn't scale particularly well.

When all else fails, there's
@other-doc['(lib "quickcheck/scribblings/quickcheck.scrbl")].

@footer-nav[
"sec:eval"
#f
]
