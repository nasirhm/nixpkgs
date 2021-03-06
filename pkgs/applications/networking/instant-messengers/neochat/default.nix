{ mkDerivation
, stdenv
, fetchFromGitLab
, pkg-config
, cmake
, qtbase
, qttools
, qtquickcontrols2
, qtmultimedia
, qtkeychain
, libpulseaudio
, olm
, libsecret
, cmark
, extra-cmake-modules
, kirigami2
, ki18n
, knotifications
, kdbusaddons
, kconfig
, libquotient
, kquickimageedit
}:

mkDerivation rec {
  pname = "neochat";
  version = "v1.0";

  src = fetchFromGitLab {
    domain = "invent.kde.org";
    owner = "network";
    repo = pname;
    rev = version;
    sha256 = "1r9n83kvc5v215lzmzh6hyc5q9i3w6znbf508qk0mdwdzxz4zry9";
  };

  nativeBuildInputs = [ cmake extra-cmake-modules pkg-config ];

  buildInputs = [
    qtkeychain
    qtquickcontrols2
    qtmultimedia
    olm
    libsecret
    cmark
    kirigami2
    ki18n
    knotifications
    kdbusaddons
    kconfig
    libquotient
    kquickimageedit
    libpulseaudio
  ];

  meta = with stdenv.lib; {
    description = "A client for matrix, the decentralized communication protocol.";
    homepage = "https://apps.kde.org/en/neochat";
    license = licenses.gpl3Only;
    platforms = with platforms; linux;
  };
}
