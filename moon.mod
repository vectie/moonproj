// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "vectie/moonproj"

version = "0.1.0-preview.1"

readme = "README.mbt.md"

repository = "https://github.com/vectie/moonproj"

license = "Apache-2.0"

keywords = [ ]

preferred_target = "native"

description = "Evidence-driven operating system for a basic one-person company"

import {
  "moonbitlang/x@0.4.46",
  "moonbit-community/rabbita@0.12.4",
  "vectie/lepusa@0.1.4",
  "vectie/moonlib@0.1.19",
  "moonbitlang/async@0.16.6",
}
