# Zig basic calculator library
Basic arithmetic evaluation using [Shunting Yards](https://en.wikipedia.org/wiki/Shunting_yard_algorithm) algorithm

# Installation
```
zig fetch --save git+https://github.com/skelitheprogrammer/zbc-lib
```
In build.zig
```
const calculator = b.dependency("zbc", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zbc", calculator.module("zbc"));
```
Import in your code
```
const calculator = @import("zbc");
```
Call 
```
try calculator.process(&input);
```



# Projects using this library
[zbc-cli](https://github.com/skelitheprogrammer/zbc-cli)

# Limitations
Currently only accepts `+`,`-`,`/`,`*`,`()` operators
