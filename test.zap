fun assert(cond: bool, msg: text) -> none
  if not cond
    throw "FAIL: {msg}"
  end
end

 @ 1. Literals & variables 
test "int literal"
  x = 42
  expect x == 42
end

test "float literal"
  pi = 3.14
  expect pi == 3.14
end

test "bool literals"
  expect true == true
  expect false == false
  expect true != false
end

test "none literal"
  n: int? = none
  expect n == none
end

test "string literal"
  s = "hello"
  expect s == "hello"
end

test "string interpolation"
  name = "Zep"
  expect "Hello {name}!" == "Hello Zep!"
end

test "multiline string"
  msg = """
Hello
World"""
  expect msg == "Hello\nWorld"
end

test "const"
  const MAX = 100
  expect MAX == 100
end

test "type annotation"
  x: int = 7
  expect x == 7
end

test "nullable type"
  v: float? = none
  expect v == none
  v = 1.5
  expect v == 1.5
end

 @ 2. Arithmetic & operators 
test "addition"
  expect 1 + 2 == 3
end

test "subtraction"
  expect 10 - 3 == 7
end

test "multiplication"
  expect 4 * 5 == 20
end

test "division"
  expect 10 / 4 == 2.5
end

test "modulo"
  expect 10 % 3 == 1
end

test "operator precedence"
  expect 2 + 3 * 4 == 14
  expect (2 + 3) * 4 == 20
end

test "unary minus"
  expect -5 == 0 - 5
end

test "increment decrement"
  x = 5
  x++
  expect x == 6
  x--
  x--
  expect x == 4
end

test "compound assignment"
  x = 10
  x += 5
  expect x == 15
  x -= 3
  expect x == 12
  x *= 2
  expect x == 24
  x /= 4
  expect x == 6.0
end

test "string concatenation"
  expect "hello" + " " + "world" == "hello world"
end

test "int to string concat"
  expect "val: " + 42 == "val: 42"
end

 @ 3. Comparison & logic 
test "equality"
  expect 1 == 1
  expect 1 != 2
end

test "comparison"
  expect 1 < 2
  expect 2 <= 2
  expect 3 > 2
  expect 3 >= 3
end

test "chained comparison"
  x = 5
  expect 0 < x < 10
  expect not (0 < 10 < x)
end

test "logic and"
  expect true and true
  expect not (true and false)
end

test "logic or"
  expect true or false
  expect not (false or false)
end

test "logic not"
  expect not false
  expect not (not true)
end

test "null coalescing"
  a: int? = none
  expect (a ?? 99) == 99
  a = 7
  expect (a ?? 99) == 7
end

test "reference equality"
  a = "hi"
  b = a
  expect a is b
end

 @ 4. Control flow 
test "if else"
  x = 10
  result = ""
  if x > 5
    result = "big"
  else
    result = "small"
  end
  expect result == "big"
end

test "else if"
  x = 5
  result = ""
  if x > 10
    result = "big"
  else if x > 3
    result = "medium"
  else
    result = "small"
  end
  expect result == "medium"
end

test "ternary"
  x = 4
  label = if x % 2 == 0 then "even" else "odd"
  expect label == "even"
end

test "unless"
  fired = false
  unless false
    fired = true
  end
  expect fired == true
end

test "unless skips on true"
  fired = false
  unless true
    fired = true
  end
  expect fired == false
end

 @ 5. Loops 
test "while loop"
  x = 0
  while x < 5
    x += 1
  end
  expect x == 5
end

test "repeat times"
  count = 0
  repeat 4 times
    count += 1
  end
  expect count == 4
end

test "repeat with index"
  sum = 0
  repeat 5 times i
    sum += i
  end
  expect sum == 0 + 1 + 2 + 3 + 4
end

test "every over list"
  nums = [1, 2, 3, 4, 5]
  sum = 0
  every n in nums
    sum += n
  end
  expect sum == 15
end

test "every over range"
  sum = 0
  every i in 1..5
    sum += i
  end
  expect sum == 15
end

test "range membership"
  expect 5 in 1..10
  expect not (11 in 1..10)
end

test "stop breaks loop"
  x = 0
  while true
    x += 1
    if x == 3
      stop
    end
  end
  expect x == 3
end

test "continue skips iteration"
  evens = 0
  every i in 1..10
    if i % 2 != 0
      continue
    end
    evens += 1
  end
  expect evens == 5
end

 @ 6. Functions 
fun add(a: int, b: int) -> int
  give a + b
end

test "basic function"
  expect add(3, 4) == 7
end

test "default parameter"
  fun greet(name: text, greeting: text = "Hello") -> text
    give "{greeting} {name}!"
  end
  expect greet("Alice") == "Hello Alice!"
  expect greet("Bob", "Hey") == "Hey Bob!"
end

test "named arguments"
  fun sub(a: int, b: int) -> int
    give a - b
  end
  expect sub(b: 3, a: 10) == 7
end

test "lambda"
  double = fun(x: int) -> x * 2
  expect double(5) == 10
end

test "closure captures scope"
  base = 100
  addBase = fun(x: int) -> x + base
  expect addBase(5) == 105
end

test "multi-return tuple"
  fun minMax(a: int, b: int) -> (int, int)
    if a < b
      give (a, b)
    else
      give (b, a)
    end
  end
  result = minMax(7, 3)
  expect result[0] == 3
  expect result[1] == 7
end

test "recursive function"
  fun fact(n: int) -> int
    if n <= 1
      give 1
    end
    give n * fact(n - 1)
  end
  expect fact(5) == 120
end

test "pipeline"
  fun double(x: int) -> int
    give x * 2
  end
  fun addOne(x: int) -> int
    give x + 1
  end
  result = 3 |> double() |> addOne()
  expect result == 7
end

 @ 7. Collections 
test "list literal"
  nums = [1, 2, 3]
  expect nums[0] == 1
  expect nums[2] == 3
end

test "list length"
  expect [1, 2, 3].length == 3
end

test "list push pop"
  a = [1, 2]
  a.push(3)
  expect a.length == 3
  v = a.pop()
  expect v == 3
  expect a.length == 2
end

test "list first last"
  a = [10, 20, 30]
  expect a.first() == 10
  expect a.last() == 30
end

test "list contains"
  a = [1, 2, 3]
  expect a.contains(2)
  expect not a.contains(9)
end

test "list map"
  doubled = [1, 2, 3].map(fun(x) -> x * 2)
  expect doubled[0] == 2
  expect doubled[2] == 6
end

test "list filter"
  evens = [1, 2, 3, 4, 5].filter(fun(x) -> x % 2 == 0)
  expect evens.length == 2
  expect evens[0] == 2
end

test "list reduce"
  sum = [1, 2, 3, 4, 5].reduce(fun(a, b) -> a + b)
  expect sum == 15
end

test "list spread"
  a = [1, 2]
  b = [3, 4]
  c = [...a, ...b]
  expect c.length == 4
  expect c[2] == 3
end

test "object literal"
  p = { x: 10, y: 20 }
  expect p.x == 10
  expect p.y == 20
end

test "object assignment"
  p = { name: "Alice" }
  p.name = "Bob"
  expect p.name == "Bob"
end

test "array destructuring"
  [a, b, c] = [10, 20, 30]
  expect a == 10
  expect b == 20
  expect c == 30
end

test "object destructuring"
  { name, age } = { name: "Alice", age: 30 }
  expect name == "Alice"
  expect age == 30
end

 @ 8. Strings 
test "string upper lower"
  expect "hello".upper() == "HELLO"
  expect "WORLD".lower() == "world"
end

test "string trim"
  expect "  hi  ".trim() == "hi"
end

test "string split"
  parts = "a,b,c".split(",")
  expect parts.length == 3
  expect parts[1] == "b"
end

test "string contains"
  expect "hello world".contains("world")
  expect not "hello".contains("xyz")
end

test "string repeat"
  expect "ab".repeat(3) == "ababab"
end

test "string length"
  expect "hello".length == 5
end

test "string index access"
  s = "abc"
  expect s[0] == "a"
  expect s[2] == "c"
end

test "string interpolation nested expr"
  x = 3
  y = 4
  expect "sum={x + y}" == "sum=7"
end

 @ 9. Type casting 
test "int to text cast"
  s = 42 -> text
  expect s == "42"
end

test "text to int cast"
  n = "7" -> int
  expect n == 7
end

test "float to int truncates"
  n = 3.9 -> int
  expect n == 3
end

 @ 10. Pattern matching 
test "match exact"
  x = 2
  result = ""
  match x
    1 -> result = "one"
    2 -> result = "two"
    _ -> result = "other"
  end
  expect result == "two"
end

test "match wildcard"
  x = 99
  result = ""
  match x
    1 -> result = "one"
    _ -> result = "other"
  end
  expect result == "other"
end

test "match range"
  x = 7
  result = ""
  match x
    1..5   -> result = "low"
    6..10  -> result = "mid"
    _      -> result = "high"
  end
  expect result == "mid"
end

test "match with when guard"
  x = 8
  result = ""
  match x
    n when n % 2 == 0 -> result = "even"
    _                 -> result = "odd"
  end
  expect result == "even"
end

test "match on type"
  v: any = "hello"
  result = ""
  match v
    int  -> result = "int"
    text -> result = "text"
    _    -> result = "other"
  end
  expect result == "text"
end

 @ 11. Error handling 
test "throw and catch"
  caught = ""
  try
    throw "oops"
  catch err
    caught = err
  end
  expect caught == "oops"
end

test "always runs on success"
  ran = false
  try
    x = 1 + 1
  always
    ran = true
  end
  expect ran == true
end

test "always runs on throw"
  ran = false
  try
    throw "err"
  catch e
    x = 1
  always
    ran = true
  end
  expect ran == true
end

test "expect throws"
  expect throws
    throw "intentional"
  end
end

test "nested try"
  inner = false
  outer = false
  try
    try
      throw "inner"
    catch e
      inner = true
    end
  catch e
    outer = true
  end
  expect inner == true
  expect outer == false
end

 @ 12. Classes & OOP 
class Counter
  pub count: int

  init()
    self.count = 0
  end

  pub fun increment() -> none
    self.count += 1
  end

  pub fun value() -> int
    give self.count
  end
end

test "class instantiation and methods"
  c = Counter()
  c.increment()
  c.increment()
  c.increment()
  expect c.value() == 3
end

test "class field access"
  c = Counter()
  c.increment()
  expect c.count == 1
end

class Animal
  pub name: text

  init(name: text)
    self.name = name
  end

  pub fun speak() -> text
    give "{self.name} makes a sound"
  end
end

class Dog from Animal
  init(name: text)
    super(name)
  end

  pub fun speak() -> text
    give "{self.name} says Woof!"
  end
end

test "inheritance super"
  d = Dog("Rex")
  expect d.name == "Rex"
end

test "method override"
  d = Dog("Rex")
  expect d.speak() == "Rex says Woof!"
end

test "parent method still works"
  a = Animal("Cat")
  expect a.speak() == "Cat makes a sound"
end

class StaticCounter
  static count: int = 0

  static fun increment() -> none
    StaticCounter.count += 1
  end

  static fun value() -> int
    give StaticCounter.count
  end
end

test "static fields and methods"
  StaticCounter.increment()
  StaticCounter.increment()
  expect StaticCounter.value() == 2
end

 @ 13. Enums 
enum Direction
  North, South, East, West
end

test "enum variant access"
  d = Direction.North
  expect d == "North"
end

test "enum match"
  d = Direction.East
  result = ""
  match d
    Direction.North -> result = "north"
    Direction.East  -> result = "east"
    _               -> result = "other"
  end
  expect result == "east"
end

enum Status
  Active   = 1
  Inactive = 0
end

test "enum with values"
  expect Status.Active == 1
  expect Status.Inactive == 0
end

 @ 14. Records 
record Point
  x: float
  y: float
end

test "record construction"
  p = Point(1.0, 2.0)
  expect p.x == 1.0
  expect p.y == 2.0
end

record Person
  name: text
  age: int
end

test "record field access"
  alice = Person("Alice", 30)
  expect alice.name == "Alice"
  expect alice.age == 30
end

 @ 15. Lazy evaluation 
test "lazy variable defers evaluation"
  computed = false

  fun expensive() -> int
    computed = true
    give 42
  end

  lazy result = expensive()
  expect computed == false
  x = result
  expect computed == true
  expect x == 42
end

test "lazy variable caches result"
  calls = 0

  fun work() -> int
    calls += 1
    give 7
  end

  lazy v = work()
  x = v
  y = v
  expect calls == 1
end

 @ 16. Generators 
test "generator yields values"
  lazy fun range(start: int, stop: int) -> int
    every i in start..stop
      yield i
    end
  end

  collected = range(1, 4)
  expect collected.length == 4
  expect collected[0] == 1
  expect collected[3] == 4
end

test "generator used in every loop"
  lazy fun evens(n: int) -> int
    every i in 0..n
      if i % 2 == 0
        yield i
      end
    end
  end

  sum = 0
  every v in evens(6)
    sum += v
  end
  expect sum == 0 + 2 + 4 + 6
end

 @ 17. Optional chaining & null safety 
test "optional chain on none returns none"
  obj: any = none
  result = obj?.name
  expect result == none
end

test "optional chain on object returns value"
  p = { name: "Alice" }
  result = p?.name
  expect result == "Alice"
end

 @ 18. Modules (stdlib) 
test "math sqrt abs floor ceil"
  use math { sqrt, abs, floor, ceil }
  expect sqrt(9.0) == 3.0
  expect abs(-5.0) == 5.0
  expect floor(3.9) == 3
  expect ceil(3.1) == 4
end

test "math pow"
  use math { pow }
  expect pow(2.0, 10.0) == 1024.0
end

test "text module"
  use text { upper, lower, trim }
  expect upper("hello") == "HELLO"
  expect lower("WORLD") == "world"
  expect trim("  hi  ") == "hi"
end

test "list module map filter reduce"
  use list { map, filter, reduce }
  expect map([1, 2, 3], fun(x) -> x * 10)[0] == 10
  expect filter([1, 2, 3, 4], fun(x) -> x > 2).length == 2
  expect reduce([1, 2, 3, 4, 5], fun(a, b) -> a + b) == 15
end

test "json round-trip"
  use json { parse, stringify }
  original = { name: "Alice", score: 42 }
  encoded  = stringify(original)
  decoded  = parse(encoded)
  expect decoded.name == "Alice"
end

 @ 19. Edge cases 
test "empty function returns none"
  fun noop() -> none
  end
  expect noop() == none
end

test "early give"
  fun earlyOut(x: int) -> none
    if x < 0
      give
    end
  end
  expect earlyOut(-1) == none
  expect earlyOut(1) == none
end

test "nested functions"
  fun outer(x: int) -> int
    fun inner(y: int) -> int
      give y * 2
    end
    give inner(x) + 1
  end
  expect outer(5) == 11
end

test "function as argument"
  fun apply(f: any, x: int) -> int
    give f(x)
  end
  expect apply(fun(n) -> n + 10, 5) == 15
end

test "list of functions"
  ops = [
    fun(x) -> x + 1,
    fun(x) -> x * 2,
    fun(x) -> x - 3
  ]
  x = 5
  every op in ops
    x = op(x)
  end
  expect x == (5 + 1) * 2 - 3
end

test "make_adder closure"
  fun make_adder(n: int) -> any
    give fun(x: int) -> x + n
  end
  add5  = make_adder(5)
  add10 = make_adder(10)
  expect add5(3) == 8
  expect add10(3) == 13
end