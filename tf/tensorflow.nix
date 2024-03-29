{ stdenv, pkgs, buildBazelPackage, lib, fetchFromGitHub, fetchpatch, symlinkJoin
, addOpenGLRunpath
# Python deps
, buildPythonPackage, isPy3k, pythonOlder, pythonAtLeast, python
# Python libraries
, numpy, tensorflow-tensorboard, backports_weakref, mock, enum34, absl-py
, future, setuptools, wheel, keras-preprocessing, keras-applications, google-pasta
, functools32
, opt-einsum
, termcolor, grpcio, six, wrapt, protobuf, tensorflow-estimator
# Common deps
, git, swig, which, binutils, glibcLocales, cython
# Common libraries
, jemalloc, openmpi, astor, gast, grpc, sqlite, openssl, jsoncpp, re2
, curl, snappy, flatbuffers, icu, double-conversion, libpng, libjpeg, giflib
# TODO default to true, provide non-gpu free option (https://groups.google.com/a/tensorflow.org/forum/#!topic/developers/iRCt5m4qUz0)
, cudaSupport ? false, nvidia_x11 ? null, cudatoolkit ? null, cudnn ? null, nccl ? null
# XLA without CUDA is broken
, xlaSupport ? cudaSupport
# Default from ./configure script
, cudaCapabilities ? [ "3.5" "5.2" ]
, sse42Support ? builtins.elem (stdenv.hostPlatform.platform.gcc.arch or "default") ["westmere" "sandybridge" "ivybridge" "haswell" "broadwell" "skylake" "skylake-avx512"]
, avx2Support  ? builtins.elem (stdenv.hostPlatform.platform.gcc.arch or "default") [                                     "haswell" "broadwell" "skylake" "skylake-avx512"]
, fmaSupport   ? builtins.elem (stdenv.hostPlatform.platform.gcc.arch or "default") [                                     "haswell" "broadwell" "skylake" "skylake-avx512"]
}:

assert cudaSupport -> nvidia_x11 != null
                   && cudatoolkit != null
                   && cudnn != null;

# unsupported combination
assert ! (stdenv.isDarwin && cudaSupport);

let
  withTensorboard = pythonOlder "3.6";

  cudatoolkit_joined = symlinkJoin {
    name = "${cudatoolkit.name}-merged";
    paths = [ cudatoolkit.out cudatoolkit.lib ];
  };

  cudatoolkit_cc_joined = symlinkJoin {
    name = "${cudatoolkit.cc.name}-merged";
    paths = [
      cudatoolkit.cc
      binutils.bintools # for ar, dwp, nm, objcopy, objdump, strip
    ];
  };

  # Needed for _some_ system libraries, grep INCLUDEDIR.
  includes_joined = symlinkJoin {
    name = "tensorflow-deps-merged";
    paths = [
      pkgs.protobuf
      jsoncpp
    ];
  };

  tfFeature = x: if x then "1" else "0";

  version = "2.0.0";
  variant = if cudaSupport then "-gpu" else "";
  pname = "tensorflow${variant}";

  pythonEnv = python.withPackages (_:
    [ # python deps needed during wheel build time (not runtime/ see the buildPythonPackage part for that)
      numpy
      keras-preprocessing
      protobuf
      wrapt
      gast
      astor
      absl-py
      termcolor
      keras-applications
      setuptools
      wheel
  ] ++ lib.optionals (!isPy3k)
  [ future
    mock
  ]);

  bazel-build = buildBazelPackage {
    name = "${pname}-${version}";

    src = fetchFromGitHub {
      owner = "tensorflow";
      repo = "tensorflow";
      rev = "v${version}";
      sha256 = "0zck3q6znmh0glak6qh2xzr25ycnhml7qcww7z8ynw2wbc75d7hp";
    };

    patches = [
      # Work around https://github.com/tensorflow/tensorflow/issues/24752
      ./no-saved-proto.patch
      # Fixes for NixOS jsoncpp
      ./system-jsoncpp.patch

      # https://github.com/tensorflow/tensorflow/pull/29673
      (fetchpatch {
        name = "fix-compile-with-cuda-and-mpi.patch";
        url = "https://github.com/tensorflow/tensorflow/pull/29673/commits/498e35a3bfe38dd75cf1416a1a23c07c3b59e6af.patch";
        sha256 = "1m2qmwv1ysqa61z6255xggwbq6mnxbig749bdvrhnch4zydxb4di";
      })
    ];

    # On update, it can be useful to steal the changes from gentoo
    # https://gitweb.gentoo.org/repo/gentoo.git/tree/sci-libs/tensorflow

    nativeBuildInputs = [
      swig which pythonEnv
    ] ++ lib.optional cudaSupport addOpenGLRunpath;

    buildInputs = [
      jemalloc
      openmpi
      glibcLocales
      git

      # libs taken from system through the TF_SYS_LIBS mechanism
      # grpc
      sqlite
      openssl
      jsoncpp
      pkgs.protobuf
      curl
      snappy
      flatbuffers
      icu
      double-conversion
      libpng
      libjpeg
      giflib
      re2
      pkgs.lmdb
    ] ++ lib.optionals cudaSupport [
      cudatoolkit
      cudnn
      nvidia_x11
    ];

    # arbitrarily set to the current latest bazel version, overly careful
    TF_IGNORE_MAX_BAZEL_VERSION = true;

    # Take as many libraries from the system as possible. Keep in sync with
    # list of valid syslibs in
    # https://github.com/tensorflow/tensorflow/blob/master/third_party/systemlibs/syslibs_configure.bzl
    TF_SYSTEM_LIBS = lib.concatStringsSep "," [
      "absl_py"
      "astor_archive"
      "boringssl"
      # Not packaged in nixpkgs
      # "com_github_googleapis_googleapis"
      # "com_github_googlecloudplatform_google_cloud_cpp"
      "com_google_protobuf"
      "com_googlesource_code_re2"
      "curl"
      "cython"
      "double_conversion"
      "flatbuffers"
      "functools32_archive"
      "gast_archive"
      "gif_archive"
      # Lots of errors, requires an older version
      # "grpc"
      "hwloc"
      "icu"
      "jpeg"
      "jsoncpp_git"
      "keras_applications_archive"
      "lmdb"
      "nasm"
      # "nsync" # not packaged in nixpkgs
      "opt_einsum_archive"
      "org_sqlite"
      "pasta"
      "pcre"
      "png_archive"
      "six_archive"
      "snappy"
      "swig"
      "termcolor_archive"
      "wrapt"
      "zlib_archive"
    ];

    INCLUDEDIR = "${includes_joined}/include";

    PYTHON_BIN_PATH = pythonEnv.interpreter;

    TF_NEED_GCP = true;
    TF_NEED_HDFS = true;
    TF_ENABLE_XLA = tfFeature xlaSupport;

    CC_OPT_FLAGS = " ";

    # https://github.com/tensorflow/tensorflow/issues/14454
    TF_NEED_MPI = tfFeature cudaSupport;

    TF_NEED_CUDA = tfFeature cudaSupport;
    TF_CUDA_PATHS = lib.optionalString cudaSupport "${cudatoolkit_joined},${cudnn},${nccl}";
    GCC_HOST_COMPILER_PREFIX = lib.optionalString cudaSupport "${cudatoolkit_cc_joined}/bin";
    GCC_HOST_COMPILER_PATH = lib.optionalString cudaSupport "${cudatoolkit_cc_joined}/bin/gcc";
    TF_CUDA_COMPUTE_CAPABILITIES = lib.concatStringsSep "," cudaCapabilities;

    postPatch = ''
      # https://github.com/tensorflow/tensorflow/issues/20919
      sed -i '/androidndk/d' tensorflow/lite/kernels/internal/BUILD

      # Tensorboard pulls in a bunch of dependencies, some of which may
      # include security vulnerabilities. So we make it optional.
      # https://github.com/tensorflow/tensorflow/issues/20280#issuecomment-400230560
      sed -i '/tensorboard >=/d' tensorflow/tools/pip_package/setup.py
    '';

    preConfigure = let
      opt_flags = []
        ++ lib.optionals sse42Support ["-msse4.2"]
        ++ lib.optionals avx2Support ["-mavx2"]
        ++ lib.optionals fmaSupport ["-mfma"];
    in ''
      patchShebangs configure

      # dummy ldconfig
      mkdir dummy-ldconfig
      echo "#!${stdenv.shell}" > dummy-ldconfig/ldconfig
      chmod +x dummy-ldconfig/ldconfig
      export PATH="$PWD/dummy-ldconfig:$PATH"

      export PYTHON_LIB_PATH="$NIX_BUILD_TOP/site-packages"
      export CC_OPT_FLAGS="${lib.concatStringsSep " " opt_flags}"
      mkdir -p "$PYTHON_LIB_PATH"

      # To avoid mixing Python 2 and Python 3
      unset PYTHONPATH
    '';

    configurePhase = ''
      runHook preConfigure
      ./configure
      runHook postConfigure
    '';

    # FIXME: Tensorflow uses dlopen() for CUDA libraries.
    NIX_LDFLAGS = lib.optionals cudaSupport [ "-lcudart" "-lcublas" "-lcufft" "-lcurand" "-lcusolver" "-lcusparse" "-lcudnn" ];

    hardeningDisable = [ "format" ];

    bazelFlags = [
      # temporary fixes to make the build work with bazel 0.27
      "--incompatible_no_support_tools_in_action_inputs=false"
    ];
    bazelBuildFlags = [
      "--config=opt" # optimize using the flags set in the configure phase
    ];

    bazelTarget = "//tensorflow/tools/pip_package:build_pip_package //tensorflow/tools/lib_package:libtensorflow";

    fetchAttrs = {
      # So that checksums don't depend on these.
      TF_SYSTEM_LIBS = null;

      # cudaSupport causes fetch of ncclArchive, resulting in different hashes
      sha256 = if cudaSupport then
        "0hvjh1amwb76w9lsqx7ahvy277fq3jj5nh6xdf0ym6dpziclcxip"
      else
        "1xpcrd90lyqxccshkrf50gr8lq596jp68igp1d4dpr2gs697liaf";
    };

    buildAttrs = {
      outputs = [ "out" "python" ];

      preBuild = ''
        patchShebangs .
      '';

      installPhase = ''
        mkdir -p "$out"
        tar -xf bazel-bin/tensorflow/tools/lib_package/libtensorflow.tar.gz -C "$out"
        # Write pkgconfig file.
        mkdir "$out/lib/pkgconfig"
        cat > "$out/lib/pkgconfig/tensorflow.pc" << EOF
        Name: TensorFlow
        Version: ${version}
        Description: Library for computation using data flow graphs for scalable machine learning
        Requires:
        Libs: -L$out/lib -ltensorflow
        Cflags: -I$out/include/tensorflow
        EOF

        # build the source code, then copy it to $python (build_pip_package
        # actually builds a symlink farm so we must dereference them).
        bazel-bin/tensorflow/tools/pip_package/build_pip_package --src "$PWD/dist"
        cp -Lr "$PWD/dist" "$python"
      '';

      postFixup = lib.optionalString cudaSupport ''
        find $out -type f \( -name '*.so' -or -name '*.so.*' \) | while read lib; do
          addOpenGLRunpath "$lib"
        done
      '';
    };

    meta = with stdenv.lib; {
      description = "Computation using data flow graphs for scalable machine learning";
      homepage = http://tensorflow.org;
      license = licenses.asl20;
      maintainers = with maintainers; [ jyp abbradar ];
      platforms = platforms.linux;
      broken = !(xlaSupport -> cudaSupport);
    };
  };

in buildPythonPackage {
  inherit version pname;

  src = bazel-build.python;

  # Upstream has a pip hack that results in bin/tensorboard being in both tensorflow
  # and the propagated input tensorflow-tensorboard, which causes environment collisions.
  # Another possibility would be to have tensorboard only in the buildInputs
  # https://github.com/tensorflow/tensorflow/blob/v1.7.1/tensorflow/tools/pip_package/setup.py#L79
  postInstall = ''
    rm $out/bin/tensorboard
  '';

  setupPyGlobalFlags = [ "--project_name ${pname}" ];

  # tensorflow/tools/pip_package/setup.py
  propagatedBuildInputs = [
    absl-py
    astor
    gast
    google-pasta
    keras-applications
    keras-preprocessing
    numpy
    six
    protobuf
    tensorflow-estimator
    termcolor
    wrapt
    grpcio
    opt-einsum
  ] ++ lib.optionals (!isPy3k) [
    mock
    future
    functools32
  ] ++ lib.optionals (pythonOlder "3.4") [
    backports_weakref enum34
  ] ++ lib.optionals withTensorboard [
    tensorflow-tensorboard
  ];

  nativeBuildInputs = lib.optional cudaSupport addOpenGLRunpath;

  postFixup = lib.optionalString cudaSupport ''
    find $out -type f \( -name '*.so' -or -name '*.so.*' \) | while read lib; do
      addOpenGLRunpath "$lib"
    done
  '';

  # Actual tests are slow and impure.
  # TODO try to run them anyway
  # TODO better test (files in tensorflow/tools/ci_build/builds/*test)
  checkPhase = ''
    ${python.interpreter} -c "import tensorflow"
  '';

  passthru.libtensorflow = bazel-build.out;

  inherit (bazel-build) meta;
}
