{ stdenv
, fetch-llvm-mirror
, fetchpatch
, perl
, groff
, cmake
, python
, libffi
, binutils
, libxml2
, valgrind
, ncurses
# , version
, release_version
, zlib
, libcxxabi
, debugVersion ? false
, enableSharedLibraries ? true
, darwin
}:

let
  version = "2a5bddd27816653b0f965426f386d5362fffe765";
  src = fetch-llvm-mirror {
    name = "llvm";
    rev = version;
    sha256 = "0j2pcv5hg4pj5mr3zj6dis8dw8gyvlsq74yrp44bby4g8m191rjv";
  };
  shlib = if stdenv.isDarwin then "dylib" else "so";

  # Used when creating a version-suffixed symlink of libLLVM.dylib
  shortVersion = with stdenv.lib;
    concatStringsSep "." (take 2 (splitString "." release_version));
in stdenv.mkDerivation rec {
  name = "llvm-${version}";

  unpackPhase = ''
    unpackFile ${src}
    # cp --no-preserve=mode -r ${src} llvm
    mv llvm-${version}* llvm
    sourceRoot=$PWD/llvm
  '';

  outputs = [ "out" ] ++ stdenv.lib.optional enableSharedLibraries "lib";

  buildInputs = [ perl groff cmake libxml2 python libffi ]
    ++ stdenv.lib.optionals stdenv.isDarwin [ libcxxabi ];

  propagatedBuildInputs = [ ncurses zlib ];

  # Patch llvm-config to return correct library path based on --link-{shared,static}.
  postPatch = stdenv.lib.optionalString (enableSharedLibraries) ''
    substitute '${./llvm-outputs.patch}' ./llvm-outputs.patch --subst-var lib
    patch -p1 < ./llvm-outputs.patch
  '';

  # hacky fix: created binaries need to be run before installation
  preBuild = ''
    mkdir -p $out/
    ln -sv $PWD/lib $out
  '';

  cmakeFlags = with stdenv; [
    "-DCMAKE_BUILD_TYPE=${if debugVersion then "Debug" else "Release"}"
    "-DLLVM_INSTALL_UTILS=ON"  # Needed by rustc
    "-DLLVM_BUILD_TESTS=ON"
    "-DLLVM_ENABLE_FFI=ON"
    "-DLLVM_ENABLE_RTTI=ON"
    "-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=WebAssembly"
  ] ++ stdenv.lib.optional enableSharedLibraries [
    "-DLLVM_LINK_LLVM_DYLIB=ON"
  ] ++ stdenv.lib.optional (!isDarwin)
    "-DLLVM_BINUTILS_INCDIR=${binutils.dev}/include"
    ++ stdenv.lib.optionals (isDarwin) [
    "-DLLVM_ENABLE_LIBCXX=ON"
    "-DCAN_TARGET_i386=false"
  ];

  postBuild = ''
    rm -fR $out

    paxmark m bin/{lli,llvm-rtdyld}
    paxmark m unittests/ExecutionEngine/MCJIT/MCJITTests
    paxmark m unittests/ExecutionEngine/Orc/OrcJITTests
    paxmark m unittests/Support/SupportTests
    paxmark m bin/lli-child-target
  '';

  preCheck = ''
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$PWD/lib
  '';

  postInstall = ""
  + stdenv.lib.optionalString (enableSharedLibraries) ''
    moveToOutput "lib/libLLVM-*" "$lib"
    moveToOutput "lib/libLLVM.${shlib}" "$lib"
    substituteInPlace "$out/lib/cmake/llvm/LLVMExports-release.cmake" \
      --replace "\''${_IMPORT_PREFIX}/lib/libLLVM-" "$lib/lib/libLLVM-"
  ''
  + stdenv.lib.optionalString (stdenv.isDarwin && enableSharedLibraries) ''
    substituteInPlace "$out/lib/cmake/llvm/LLVMExports-release.cmake" \
      --replace "\''${_IMPORT_PREFIX}/lib/libLLVM.dylib" "$lib/lib/libLLVM.dylib"
    install_name_tool -id $lib/lib/libLLVM.dylib $lib/lib/libLLVM.dylib
    install_name_tool -change @rpath/libLLVM.dylib $lib/lib/libLLVM.dylib $out/bin/llvm-config
    ln -s $lib/lib/libLLVM.dylib $lib/lib/libLLVM-${shortVersion}.dylib
    ln -s $lib/lib/libLLVM.dylib $lib/lib/libLLVM-${release_version}.dylib
  '';

  doCheck = false; # stdenv.isLinux;

  checkTarget = "check-all";

  enableParallelBuilding = true;

  passthru.src = src;

  meta = {
    description = "Collection of modular and reusable compiler and toolchain technologies";
    homepage    = http://llvm.org/;
    license     = stdenv.lib.licenses.ncsa;
    maintainers = with stdenv.lib.maintainers; [ lovek323 raskin viric dtzWill ];
    platforms   = stdenv.lib.platforms.all;
  };
}
