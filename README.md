# ⚡ Zep

> A fast, simple, and readable programming language. Easier than Python — bytecode compilation with a stack-based VM.

---

## Features

- Clean, readable syntax — no semicolons, no colons
- Optional type annotations
- Bytecode compilation
- Stack-based VM
- Embeddable as a Haxelib
- Null safety
- Pattern matching
- Classes & interfaces
- Modules & imports
- Lambdas & pipelines
- Built-in error handling

---

## Hello World

```zep
say "Hello, World!"
```

---

## Table of Contents

- [Variables](#variables)
- [Types](#types)
- [Functions](#functions)
- [Control Flow](#control-flow)
- [Loops](#loops)
- [Classes & OOP](#classes--oop)
- [Error Handling](#error-handling)
- [Modules](#modules)
- [Quality of Life](#quality-of-life)

---

## Variables

```zep
@ Untyped
x = 10
name = "Alice"
alive = true

@ Typed
x: int = 10
name: text = "Alice"
score: float = 3.14
alive: bool = true

@ Nullable
x: int? = none

@ Constants
const MAX_HEALTH = 100
const VERSION = "1.0.0"
```

---

## Types

| Type      | Example             | Description     |
| --------- | ------------------- | --------------- |
| `int`     | `42`                | Whole number    |
| `float`   | `3.14`              | Decimal number  |
| `text`    | `"hello"`           | String          |
| `bool`    | `true`              | True or false   |
| `list<T>` | `[1, 2, 3]`         | Typed array     |
| `map`     | `{ name: "Alice" }` | Key-value pairs |
| `any`     | anything            | No type check   |
| `none`    | —                   | No return value |

### Type Alias

```zep
alias ID = int
alias Name = text
alias Point = (float, float)
```

### Equality Operators

| Operator | Meaning                 | Example      |
| -------- | ----------------------- | ------------ |
| `==`     | Same value              | `x == 5`     |
| `!=`     | Different value         | `x != 5`     |
| `is`     | Same object (reference) | `a is b`     |
| `is not` | Different object        | `a is not b` |

```zep
a = "hello"
b = "hello"
c = a

say a == b       @ true  — same value
say a is b       @ false — different objects
say a is c       @ true  — same object

x = 10
say x == 10      @ true
say x != 5       @ true
```

```zep
n: int = "42" -> int
s: text = 42 -> text
```

---

## Functions

```zep
@ Basic
fun greet(name: text) -> none
  say "Hello {name}!"
end

@ With return
fun add(a: int, b: int) -> int
  give a + b
end

@ Default parameters
fun greet(name: text, greeting: text = "Hello") -> none
  say "{greeting} {name}!"
end

@ Named arguments
greet(name: "Alice", greeting: "Hey")

@ Multiple return values
fun minMax(nums: list<int>) -> (int, int)
  give (nums.min(), nums.max())
end

(min, max) = minMax([3, 1, 4, 1, 5])

@ Lambda
square = fun(x: int) -> x * x
```

---

## Control Flow

```zep
@ If / else
if age >= 18
  say "Adult"
else if age >= 13
  say "Teen"
else
  say "Child"
end

@ Inline if (ternary)
status = if alive then "alive" else "dead"

@ Logic operators
if x > 0 and x < 100
  say "in range"
end

if dead or hurt
  say "game over"
end

if not alive
  say "respawning"
end

@ Value equality
if name == "Alice"
  say "hi Alice"
end

if name != "Bob"
  say "you are not Bob"
end

@ Reference / same object
if a is b
  say "same object"
end

if a is not b
  say "different objects"
end

@ Pattern matching
match x
  1       -> say "one"
  2       -> say "two"
  3..10   -> say "three to ten"
  _       -> say "other"
end

@ Match on type
match value
  int  -> say "its a number"
  text -> say "its a string"
  _    -> say "unknown"
end
```

---

## Loops

```zep
@ Repeat N times
repeat 5 times
  say "Hello!"
end

@ Repeat with index
repeat 5 times i
  say i
end

@ While loop
x = 0
while x < 10
  say x
  x += 1
end

@ For each
names = ["Alice", "Bob", "Charlie"]
every name in names
  say "Hi {name}"
end

@ Range
every i in 0..10
  say i
end

@ Range check
if x in 0..100
  say "valid"
end
```

---

## Classes & OOP

```zep
@ Basic class
class Dog
  pub name: text
  priv health: int

  init(name: text)
    self.name = name
    self.health = 100
  end

  pub fun bark() -> none
    say "{self.name} says Woof!"
  end
end

d = Dog("Rex")
d.bark()

@ Inheritance
class Animal
  name: text

  init(name: text)
    self.name = name
  end

  fun speak() -> none
    say "{self.name} makes a sound"
  end
end

class Cat from Animal
  init(name: text)
    super(name)
  end

  fun speak() -> none
    say "{self.name} meows!"
  end
end

@ Interface
interface Flyable
  fun fly() -> none
  fun land() -> none
end

class Bird from Animal is Flyable
  init(name: text)
    super(name)
  end

  fun fly() -> none
    say "{self.name} is flying!"
  end

  fun land() -> none
    say "{self.name} landed!"
  end
end

@ Abstract class
abstract class Shape
  abstract fun area() -> float

  fun describe() -> none
    say "Area: {area()}"
  end
end

@ Static members
class Counter
  static count: int = 0

  static fun increment() -> none
    Counter.count += 1
  end
end

@ Generics
class Box<T>
  value: T

  init(value: T)
    self.value = value
  end

  fun get() -> T
    give self.value
  end
end

box = Box<int>(42)
say box.get()
```

### OOP Keywords

| Keyword     | Meaning                  |
| ----------- | ------------------------ |
| `class`     | Define a class           |
| `init`      | Constructor              |
| `self`      | Current instance         |
| `super`     | Parent constructor       |
| `from`      | Inherit a class          |
| `is`        | Implement interface      |
| `interface` | Define interface         |
| `abstract`  | Abstract class or method |
| `static`    | Class-level member       |
| `pub`       | Public                   |
| `priv`      | Private                  |

---

## Error Handling

```zep
@ Try / catch / always
try
  x = divide(10, 0)
catch err
  say "Error: {err}"
always
  say "done"
end

@ Throw errors
fun divide(a: int, b: int) -> float
  if b is 0
    throw "Cannot divide by zero"
  end
  give a / b
end

@ Custom error types
type MyError
  message: text
  code: int
end

@ Catch specific types
try
  riskyOp()
catch err: NetworkError
  say "Network failed"
catch err: ValueError
  say "Bad value"
catch err
  say "Unknown: {err}"
end

@ Result type (Rust style)
fun divide(a: int, b: int) -> int | error
  if b is 0
    give error("divide by zero")
  end
  give a / b
end

result = divide(10, 2)
if result is error
  say "Failed!"
else
  say result
end
```

---

## Modules

```zep
@ Import whole module
use math

@ Import specific items
use math { sqrt, pow }

@ Import with alias
use net.http as http

@ Declare a module
module utils

pub fun square(x: int) -> int
  give x * x
end

@ Private by default
fun secret() -> none
  say "internal only"
end
```

### Standard Library

| Module     | Contents                          |
| ---------- | --------------------------------- |
| `math`     | `sqrt, pow, abs, floor, ceil`     |
| `text`     | `split, join, trim, upper, lower` |
| `list`     | `sort, filter, map, reduce`       |
| `io`       | `readFile, writeFile`             |
| `net.http` | `get, post, put, delete`          |
| `time`     | `now, sleep, format`              |
| `json`     | `parse, stringify`                |
| `os`       | `env, args, exit`                 |

---

## Quality of Life

```zep
@ String interpolation
say "Hello {name}, you are {age} years old!"
say "Next year: {age + 1}"

@ Multiline strings
msg = """
Hello World
This is Zep
"""

@ Pipeline operator
result = name
  |> split(" ")
  |> first()
  |> upper()
  |> trim()

@ Destructuring
[a, b, c] = [1, 2, 3]
{ name, age } = person
[a, b] = [b, a]        @ swap

@ Spread operator
combined = [...a, ...b]

fun sum(...nums: list<int>) -> int
  give nums.reduce(fun(a, b) -> a + b)
end

@ Optional chaining
name = user?.profile?.name
age  = user?.profile?.age ?? 0

@ Shorthand operators
x += 5
x -= 3
x *= 2
x /= 4
x++
x--
```

### Built-in Methods

```zep
@ Text
"hello".upper()             @ "HELLO"
"HELLO".lower()             @ "hello"
"hello world".split(" ")   @ ["hello", "world"]
"  hi  ".trim()             @ "hi"
"hi".repeat(3)              @ "hihihi"
"hello".contains("ell")    @ true
"hello".length              @ 5

@ List
nums.length
nums.push(6)
nums.pop()
nums.first()
nums.last()
nums.reverse()
nums.sort()
nums.contains(3)
nums.map(fun(x) -> x * 2)
nums.filter(fun(x) -> x > 2)
nums.reduce(fun(a, b) -> a + b)
```

---

## Full Example

```zep
use math { sqrt }

class Player
  pub name: text
  priv health: int
  priv score: int

  init(name: text)
    self.name = name
    self.health = 100
    self.score = 0
  end

  pub fun takeDamage(dmg: int) -> none
    self.health -= dmg
    if self.health < 0
      self.health = 0
    end
  end

  pub fun addScore(pts: int) -> none
    self.score += pts
  end

  pub fun isAlive() -> bool
    give self.health > 0
  end

  pub fun status() -> none
    say "{self.name} | HP: {self.health} | Score: {self.score}"
  end
end

@ Main
p = Player("Alice")
p.addScore(100)
p.takeDamage(30)
p.status()

if p.isAlive()
  say "{p.name} is still alive!"
end
```

---

## Comments

```zep
@ This is a single line comment

@--
  This is a
  multi line comment
--@
```

---

## Quick Reference

| Feature         | Syntax               |
| --------------- | -------------------- |
| Print           | `say value`          |
| Return          | `give value`         |
| Comment         | `@ ...`              |
| Value equal     | `==`                 |
| Value not equal | `!=`                 |
| Same object     | `is`                 |
| Not same object | `is not`             |
| Logic           | `and` `or` `not`     |
| Null            | `none`               |
| Nullable type   | `type?`              |
| Cast            | `value -> type`      |
| Ternary         | `if x then a else b` |
| Pipeline        | `x \|> fn()`         |
| Spread          | `[...list]`          |
| Optional chain  | `x?.y?.z`            |
| Null default    | `x ?? default`       |
| Range           | `0..10`              |
| Lambda          | `fun(x) -> x * 2`    |
| Match           | `match x`            |
| Constant        | `const X = value`    |
| Type alias      | `alias X = type`     |

---

## Execution Model

```
zep main.zep
    ↓
Bytecode Compiler      ← compiles to bytecode internally
    ↓
Stack-based VM         ← executes bytecode on a value stack
```

| Stage                 | Description                                               |
| --------------------- | --------------------------------------------------------- |
| **Source → Bytecode** | Zep compiles `.zep` to bytecode automatically             |
| **Stack-based VM**    | Pushes and pops values on a stack to execute instructions |

### How the Stack VM works

```
@ Zep code
x = 2 + 3

@ Bytecode
PUSH  2       @ stack: [2]
PUSH  3       @ stack: [2, 3]
ADD           @ stack: [5]
STORE x       @ stack: []

@ Function call
say(add(1, 2))

@ Bytecode
PUSH   1      @ stack: [1]
PUSH   2      @ stack: [1, 2]
CALL   add    @ stack: [3]
CALL   say    @ stack: []
```

```zep
@ Just run it — everything happens automatically
zep main.zep
```

> Zep — Simple syntax. Fast execution. Fun to write. ⚡
