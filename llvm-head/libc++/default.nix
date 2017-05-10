{ lib, stdenv, fetch-llvm-mirror, cmake, llvm, libcxxabi, fixDarwinDylibNames }:

let version = "57c405955f0abd56f81152ead9e2344b532276ad";
in stdenv.mkDerivation rec {
  name = "libc++-${version}";

  src = fetch-llvm-mirror {
    name = "libcxx";
    rev = version;
    sha256 = "028c8mjh20djzfbfgz90i71ylq79wzr3q4pc7alvf8pva8h2si49";
  };

  postUnpack = ''
    # TODO
    unpackFile ${libcxxabi.src}
    export LIBCXXABI_INCLUDE_DIR="$PWD/$(ls -d libcxxabi-${version}*)/include"
  '';

  # https://github.com/llvm-mirror/libcxx/commit/bcc92d75df0274b9593ebd097fcae60494e3bffc
  patches = [ ./pthread_mach_thread_np.patch ];

  prePatch = ''
    substituteInPlace lib/CMakeLists.txt --replace "/usr/lib/libc++" "\''${LIBCXX_LIBCXXABI_LIB_PATH}/libc++"
  '';

  preConfigure = ''
    # Get headers from the cxxabi source so we can see private headers not installed by the cxxabi package
    cmakeFlagsArray=($cmakeFlagsArray -DLIBCXX_CXX_ABI_INCLUDE_PATHS="$LIBCXXABI_INCLUDE_DIR")
  '';

  nativeBuildInputs = [ cmake ];

  buildInputs = [ libcxxabi ] ++ lib.optional stdenv.isDarwin fixDarwinDylibNames;

  cmakeFlags = [
    "-DLIBCXX_LIBCXXABI_LIB_PATH=${libcxxabi}/lib"
    "-DLIBCXX_LIBCPPABI_VERSION=2"
    "-DLIBCXX_CXX_ABI=libcxxabi"
  ];

  enableParallelBuilding = true;

  linkCxxAbi = stdenv.isLinux;

  setupHook = ./setup-hook.sh;

  meta = {
    homepage = http://libcxx.llvm.org/;
    description = "A new implementation of the C++ standard library, targeting C++11";
    license = with stdenv.lib.licenses; [ ncsa mit ];
    platforms = stdenv.lib.platforms.unix;
  };
}
