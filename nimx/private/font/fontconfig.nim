when defined(js): {.error: "This file is not supposed to be used in JS mode".}

import os, dynlib, strutils

const fontSearchPaths = when defined(macosx):
  [
    "/Library/Fonts"
  ]
elif defined(android):
  [
    "/system/fonts"
  ]
elif defined(windows):
  [
    r"c:\Windows\Fonts" #todo: system will not always in the c disk
  ]
elif defined(emscripten):
  [
    "res"
  ]
else:
  [
    "/usr/share/fonts/truetype",
    "/usr/share/fonts/truetype/ubuntu-font-family",
    "/usr/share/fonts/TTF",
    "/usr/share/fonts/truetype/dejavu",
    "/usr/share/fonts/dejavu",
    "/usr/share/fonts"
  ]

iterator potentialFontFilesForFace*(face: string): string =
  for sp in fontSearchPaths:
    yield sp / face & ".ttf"
  when not defined(emscripten):
    yield getAppDir() / "res" / face & ".ttf"
    yield getAppDir() /../ "Resources" / face & ".ttf"
    yield getAppDir() / face & ".ttf"


const useLibfontconfig = defined(posix) and not defined(android) and not defined(ios) and not defined(emscripten)


when useLibfontconfig:
  proc loadFontconfigLib(): LibHandle =
    loadLib("libfontconfig.so")

  proc getFcWeight(face: var string, weightSymbol: string): bool =
    # face and weightSymbol must be lowercase!
    # Find weightSymbol in face. e.g. face ends with "-Bold"
    # and weightSymbol is "bold. If found modify modify face so
    # that it doesn't contain weight, and return true. Return false
    # otherwise.
    let lSuffix = "-" & weightSymbol
    result = face.endsWith(lSuffix)
    if result:
      face.delete(face.len - lSuffix.len, face.high)

  proc findFontFileForFaceAux(face: string): string =
    let m = loadFontconfigLib()
    if m.isNil: return

    type
      Config = ptr object
      Pattern = ptr object

    template p(s: untyped, t: untyped) =
      let s = cast[t](symAddr(m, astToStr(s)))
      if s.isNil:
        unloadLib(m)
        return

    p FcPatternCreate, proc(): Pattern {.cdecl.}
    p FcPatternAddString, proc(p: Pattern, k, v: cstring): cint {.cdecl.}
    p FcPatternAddInteger, proc(p: Pattern, k: cstring, v: cint): cint {.cdecl.}
    p FcConfigSubstitute, proc(c: Config, p: Pattern, kind: cint): cint {.cdecl.}
    p FcDefaultSubstitute, proc(p: Pattern) {.cdecl.}
    p FcFontMatch, proc(c: Config, p: Pattern, res: ptr cint): Pattern {.cdecl.}
    p FcPatternGetString, proc(p: Pattern, obj: cstring, n: cint, s: var cstring): cint {.cdecl.}
    p FcPatternGetInteger, proc(p: Pattern, obj: cstring, n: cint, s: var cint): cint {.cdecl.}
    p FcPatternDestroy, proc(p: Pattern) {.cdecl.}
    p FcConfigAppFontAddDir, proc(c: Config, d: cstring): cint {.cdecl.}


    proc getString(p: Pattern, k: cstring, n: cint): string =
      var t: cstring
      if FcPatternGetString(p, k, n, t) == 0:
        result = $t

    when defined(linux):
      discard FcConfigAppFontAddDir(nil, getAppDir() / "res")
    elif defined(macosx):
      discard FcConfigAppFontAddDir(nil, getAppDir() /../ "Resources")

    let pat = FcPatternCreate()
    var face = face.toLowerAscii
    if getFcWeight(face, "black"):
      discard FcPatternAddString(pat, "family", face)
      discard FcPatternAddInteger(pat, "weight", 210)
    elif getFcWeight(face, "bold"):
      discard FcPatternAddString(pat, "family", face)
      discard FcPatternAddInteger(pat, "weight", 200)
    elif getFcWeight(face, "regular"):
      discard FcPatternAddString(pat, "family", face)
      discard FcPatternAddInteger(pat, "weight", 80)
    else:
      discard FcPatternAddString(pat, "family", face)

    discard FcPatternAddString(pat, "fontformat", "TrueType")

    discard FcConfigSubstitute(nil, pat, 0)
    FcDefaultSubstitute(pat)
    var res: cint
    let match = FcFontMatch(nil, pat, addr res)

    result = match.getString("file", 0)

    # var index: cint
    # discard FcPatternGetInteger(match, "index", 0, index)

    FcPatternDestroy(pat)
    FcPatternDestroy(match)

    unloadLib(m)

    # TODO: Our glyph rasterizer (stb_truetype) supports only ttf.
    # We should have gotten a ttf file by now, but verify it
    # just in case.
    if not result.endsWith(".ttf"):
      result = ""

proc findFontFileForFace*(face: string): string =
  when useLibfontconfig:
    result = findFontFileForFaceAux(face)
    if result.len != 0: return

  for f in potentialFontFilesForFace(face):
      if fileExists(f):
          return f
