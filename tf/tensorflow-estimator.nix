{ stdenv, fetchPypi, buildPythonPackage
, numpy
, absl-py 
, mock
}:

buildPythonPackage rec {
  pname = "tensorflow-estimator";
  version = "2.0.0";
  format = "wheel";

  src = fetchPypi {
    pname = "tensorflow_estimator";
    inherit version format;
    sha256 = "1nkjlwlnpr1avwdl3kmj5h25gg9vsk729mf6kdbjfinm2a3zxzal";
  };

  propagatedBuildInputs = [ mock numpy absl-py ];

  meta = with stdenv.lib; {
    description = "TensorFlow Estimator is a high-level API that encapsulates model training, evaluation, prediction, and exporting.";
    homepage = http://tensorflow.org;
    license = licenses.asl20;
    maintainers = with maintainers; [ jyp ];
  };
}

