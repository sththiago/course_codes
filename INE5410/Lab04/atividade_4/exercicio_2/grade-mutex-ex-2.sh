#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

echo -e "Grade for $BASE$EXT: $(cat grade)"

cleanup || true

exit 0

__TESTBENCH_MARKER__
� *�[ �=�v�6������KD�dK�u�9ql������I�=<��ܖHI�o㏙�{�!O�	�c[�	� )�����<'q(
�BU�P�"F���_�<�jO����b����ϳ����z��������^]{�~F6�I�3#' �3���0����D��G�?
���}��6֞��Q���_΀6�9n�p}��������h�xFZGB��'�����K�[�t�����^w�]����tV+�G�Ϻk��������z��^oݟ���HuA�V�?�Ib���Y�Qe��%�Gj!�Y`8��B����z��IH��
������2�=Zq���X�k�"ڿ�I���Ͽ����1��Q��pB��d�!���ğ�����*43���/	ΐ\J4!�lBf"\�~�	����R�tTV3��.�l��#[�&	���nD�8&�2t	���VEοy�C��1�h�2V���ا��������G]���';{=����)e�}��+�i~���"��~q�����#r4�F {#Z��)8T��h��.���"L
5M�B�n������舽4��";#����A�����\sz�\�r���^�5��Q��{�"R��' ���r��>�.Ԯ�"��5(����???��ު�Vq����搴Is������m[�#Q�Ӽ����V|�p�u9��/�j�y۲d'Y��}뢾UF �$�����+�Tb�jּ)�,�MG!-ǣ(�*Wq��J0F�S2P�����n��{}|�m%ƨ��}U�t6��#]�:�x���A�f��T�5�5�I������	_=��jU�Z�
� d{;3\�I��W�@#V�b,FAJ�\Z�#YGq����~qR弃�ل�O����!9�..�ϫ�z��Z|�V����Q��,E�2�)����a�S@��Wa�H�ʵ�1,��_���f�|��/�Z++W�XU��)�J�\3�9����8#w�D~Ќ˖��4�������f��o�מ��c<����!���������g�ӳz��?�?�ve�]X���y�돦���F'�Z��V����� @w�bfG���Q�(����I,zV�r�| ����f��JQ�7����؂i����^�5g/ V�.���m`��כ��?y�D�k�&BJ�^�^y�sF>8,��M�I-��b��y�@[��s�\_�
Z�x��������k>��[O��1m麾�r�0�A�����c�.���L�����4<��������>L(�&�b>1gES��ĉ�;��wf��	'�7��oyŏ��z�ߣ�ީ��k4���kհ<�<=�?<8/kg���9����}�N��G��K�:��w׸c��	*��qj��0�ڨ׼+x���>��%��e��A�2�4H�A�t�l?� k�n@S�9����$Q��A���JA'h,Fe	U�l_�	�6����?�����9�3��ұ
�O������wF�k)��i$	����n�D�g�0�b���ɇ`m#�ʉ8Tu��-���&�l�+����w	7kÆ� Pv������_^3y���,��~P��1*�,�/����n:0�(��̎e��mH�
nu�������p�����f��HF²[��0�y�s=�$+{a����~����~b�NJ�4 k����~T9E��_jX�����`��%�	F_�N���ʍ�2�����{�f`�᫃���(�����xV���j�� �aQ�b�%������r������7�پ s]�͹���u�5�f��������5(��P�d̆2�!��f����-��@u��ϙUZ��*�C�D�(�F �	B֫����5j��F�|$��E3���d���(���ar?�;���A�1a��[��U+A�j��r~M�Ը"��ͺ���F�Juj�%+9�1�s�n�;��+e��"�w�/�~Ӎ���u�P�g^�����8���������.8B�mJ�*�ba#�E��ݪ�J4
�`#�3:�'�Qɠ P�zנ`9��C@�f'ln�7e ��aйK����A.0�8� ����ޚ�ΘC�-T����tB��1>���]�7U؜�nj���8��l_���bc6���N���c��O�kԂ���Gi�om=��_[{:�{�'�5�ٿ��w����iD�3��E�mL��fKM=C!j���<���b�����>��.Ԇ�!;�k�6j��l��Iw��^��΀�ב�EG����kۯN{�����������t���k��:��uW[�o[9�6,�a��=��1�h�?L��t��������x��?�c����t���ˍ�����95��ց�g��B�W"�:pМ���0>?��UI�\���`��8ի\��f��[ũW(1{�0)�x5m'!M����{9�l'B�g�/�Ȫ!@�Ơ�� ����+W��#��}� hXL rx?���I�R���a
����{�v����¤i���ɩ��x�1�~]C�@V�E˂�l��CfA:#a�,3^I1�$�r8y�ɶC}]�1H�)=�G�C^������"���5Dh���2E���
����aS�s@����r<��|���?��_��_]�����o=���xL�p�Ū��,0}�( ��pp2r\�;�������
�S��T(4�zX�-D'.rC;��i�74)E{�}�E�Pn}DU�KV*
s�:�[���i'�w��>�y*g��	��s�)Y�����AD6cB�?�T�a���(m,����7�����Wi�~yu�{m����d�G藍[L�|�쮷��N �<���(
������G�]c�4[����[��!�UJ�e�Y,nϜ�T{��2�q�y<LXygd�����xTc�3Ij5Ӻ�[�+���� J�A��ۙn���r���Ȑ+�[��]TM��A�"���9�6���#�{�ݒ<�ݟz�?�{�ӳ����	T��1�S��8��(���8\k>ϫ�Qg��IC���M/Yf���q�9��������A�H�I�u6��
�\�,}+��j����p��#2]c�3	�fA$�2'�"QZ�lj���鍨8��0X,!/Aud��e�ݴB�2]n!�N�	�Y\�r�՞3��������%���C��Q�0wG'L;������L7x�8x<'�����=��v_�����gi�7��9EK�A��y�#כ���%�	��G�0�����Ȥ�+�L�Xu�$=Yy��-%�j#l��	�P0��U++{>yG�Gyj�Gה/��3%X9��+���1o��z��mK9 ,�&�xp��1����1��t�c���ba��iS%8�/ٝ�E��%1���I���H�u���4Γ�z⭌��h!���f03y���R��Ӫ.F]튠M��$����Y��)�P'��v�U�?��O�9�3���.��BG�����P(W��u痩d�+���Y(⃞�Q��g6ex�f��O�����e�4��X���%,�^��-$�,��x3Ζ4J�%��m�S)�3��b�)"m� ��]��;���ċL�xo�4�7��4��P2��[X<K9f���T�]N]6	���Hg~J�#�w����R�c���������_b6�V�b!�5���7!������B�|�������G{F�*��R�!!?>q.y�ig5�\d#H�Q<�zT�~(~���Y�.B[��Ij�<�{T/�Q̂H"c\�Y�����g���Y*�WPk���X�bX��#��C�=��`���%N�\�w=Ļ��{(��d��h��h�`����֍E��<�����1���lDp�jC�4��H�ah	����70?����	��X�Vfm�8��3t����F4�VYqB�mc���R�eX�%{u�r�����(��%`6�x�����D�,���sC{�w^�%�o~$ /��5*�9���ܨ�ꪲ�:E]rnf2��{�*��
w��ڔHJa��>���4�1K�/.�V5��H�H�=��}qb:������=Nj��N��yT&��K����,��x��H�f�E*�\����G\6N������2gX�KK$#@�B\�Ɇa4�Y������u���R枅�#� ��>��O�����1V��1�S s�͝Ͽ�̋�9s�(pn� �d�<�*窍�"��R20�yR�0>f~��iPdM|`��H��-��R05Ei%O2��3J1�wM���E�{�ë��w�C�_�cd��Oq^�ȹN���R�Ux�y�y���	4��g��?�L�A�c���3���"ǢNb�֝�A+V<1L3�0��1(��ct]�_�(ud�(�f��Bh��> ,�>��ǆ�e��U��m�h��Q|�!��`�|�vP�6�#��IH�I�����Bu���O˖R:@0���Y�%z'�J�^8!�;�~�hًUb6�"%C[򩔌��mL�`)LhX�I�j��������f?07�]®[�.�r���BʋH�N ���{ʬ1�3ɴ{�>ʾ�h�3����O������8��?��9��D���M0y�<�I?���������L����ّ�xb�AS-�F�-D�����"���eA�1?��:&+�?���O9R:��N�����*?
�W�2�t�M�Q*����qW�i �$��h�ٞ1�ڳc@���,�3[}��B6f�}y�9��A,��:8��h�Y�oa���	�y��9mg�.�>�PW�ӧڧ��?��ok/^����O��Q��7�9�}�a�!�6��K��������qaڸ���פ%#�I#��)�-��0�]B��K��#:�t{�W�q�Al�
C�Θ�o:��3)3�Ue�7'���G*K*�8$ln+N�vST�ӥ�q*�V��-�װ�R��GLe���3I���v)�>��T�"O�p�VMP��5��_.�+����kB`��1+�����b�S��i�Z&��Y���e�	��}�53�˝)���So�$$���c��zMv�W��$W�Lf	Z�\բD�?�~i)-؆�voK~��b6�,�|'�Q_%[���I�ՀQ
��%�Y}fwb�E�	��J
�F#�	v���F�:���$�b⥊Br�IT�E,L��Ss���p��RlL&�b�g�L������)4,F���Q�	� �����V��ߵͧ��1�SQ��o�sީ7(�����|�\1ި ~��A���@�9cǻ���(p?��NG,�m�\t���1]/��/�e_7�;�������/7qDABf��9 ˨���D�}q'`0�x_�3h����F5�<�=4�'L�$�����K�$Κ�	^sq��"�	��d���t�f�u�^��*c:� 8�ެ�
> �����BydU]d)<	,R�"��BK��Q��|� �[a�����,�<���%�r��3	GL<�R�F����4�um���[�k�W�b$@]4�z��V�%t��B��A�S5��E&j�z"�]�c�8W&7ǜ7���0%��}�?�B���w�^�dq ���!��L	Dl�S�����+hk��C�n��2d�z�9	 0��1-�X#C���`P�N���\���P��\�)V��L��,��A�2�8�Z�Q�kv����L1nyR�Y�?��+e����jl�e���
9v���;{c�G�൮͐�w�WX�����b���J���/h�[����}�����e�Ӊt� .C�n�Y���h�[|�MS�"Q��}А�^Hs���V*�V�8�9������J��o�vT�1<�=�ܮ.U6xbJN�^Lz�u[��:0)6�w�}7�)�Lȉ�;<r�$-D�F�����D��yD�N�`뢡{+���;%K�V�h���� l��I�mX��;����k�v˵��_Ǽ�M�)��q�z�Y���>�7�<���'>�R^�>�����7�n�e��jm��嵫�E6u��u0�F����N[a�0�j��Xs}�����9L9�S��=�0&`�`�M���A��9@ela���Q<i<͡9Un�"��vG�񦓬�L�I�8�����-�����C��)����l�6�R���i�������/V�/�5�d_V���>��Dp$`�E�b�7��[���:;~u��q)�U�m+�d��^�vOm�o�� �i����]v�M\l��_{���q���_1R�bw�KI[Vݦ�,�*d˵\E�#r��z��p�mb�?Ə5�'#/y�?��̅�����@0�$�gfΜ9�93�H���o��<���U_��=�@}��"�:LQQL�tۋdƿ�37Y�v "�f�Cͳ�k&��zW R��'�%u��9z�]8D7j.�#?�JI���/�pǲz��w��>�y�P��s��A����w���{DrE4�?����Q.���U!��Y��V��Բq)f�_죏ܒ��|����?�����y�^kb��C����}l�(W�A:��^O�^�����Va��)�@#��1�/�#��e��g��xA���$�I�eẔ���mU��-.���\e�
Lu�ik�i��[D�;ǯ�E�>|�mf|-��$o������f���7�g��� ��m�gm��������R�竟S8=�~�:���<�d{��0`���{�9��yqG����s[�]zdm�޳K�J�kƦK�,U��Wβ�Ū�z�gSw}�z�Ihhki�G�N�v����O(Z��S
;�xﲊ;7�ʴɝ&�H��LIX����A��64��qaM��ݹ�M��@��q�ȡ	�;CӔ�ܒ��<c<��L��V�DH��u�(�3(���%.a�?}}G������*d�Nq[bf�o�i�u�B�v[�RX'�4�ż���"�a�\�V3��]��le�1j���-5�.{�VUcX|_Tgu��P9TS@oei��&��d��9���J��-�I��k��ZN��ٞ[ǺtU�֔�V���o��ee��VcŔ�N}���p�6��j�r}T�h�}{��i%�_�+6js�f�Z��Ir��;-��ǟ0�<�z���ք��oU��O�'j�Ye�2�<�>s��*�N�48�6o����8R����l�/��m�����������*p����ӳ��O�>L��t�.�'4y��r/��&j�L�'�_��,e��'�Ϗ�ƔQ:����K�0:)�HU�.��W�DZ�%Y�s�7���C%��!;�y.R�@�,�m��1�Ϩz��	U"0�[�"D�I��ר���B�+U�v�9LI�� ���CE:՝��G8};^}`��"�5�<�z������YdTm�C����d�'Z*D�(ذj��eQ,F;;DO��x �d��p.���Mz;<^�y$�/�l`87�~L����;�f�������ٳ�������2��;۽�U��,�s�����Mwh��0�7}o5Ϧ��}~��x��OT�<f�0B��fꃬt&��>��ZQ��+��R1NHq���A
ž-O�:���9e#[��J*�a��5�\К�SNQ�]==}��O�N�����������Б/dy.� T�6��7}��u\ݭ����=���Fg�ui0�34�&R�|��BK��A�Ԕ+e�6���
��U��p%��	]�C�S\g��U7_�����GԌۊjCe�I`|�uwʰp��JY�ޓ���� v�*�펼�-}����mw q��_v�8�?V����
���'B؝P�:[f��j[F�g�^7��o���T_�'���Ȍ����|µb�7��-��E�;Z��H��j��9Tk��\��Ap2��!�k��EYmsTk^PY\Y��i!S��U�m���E�`���h��P�]=�٤��j�C��]} ����'h�z?�T��|���2ħ��	�à�q���ullw �l�5���k�u�d���=H�������@-""t4�H�p3����V�����.��Q�c����&���؀�%[�`��AC"�2�(��GHR��#"iC���2�9ip`�[��	:�ESh�B�Z���ȅ
�Cءp�N9�ER:E!���������S2�
�O]�OZw��d[k|Ͱ6��֦��,�|L3�ꐽ�"87+��CN�W?ϓ���D�2���e�C�E�~�\A.��X�X�[U#�i�	*��Z��2ڐ8I
��q���S�>���r��g��\Y$�����<�L���4y��7��=��s�X��`�^4t��4]����ў`�N�+�kU
��'�@��2��"!��l���[�X<b4��h��2��8ϵ!�M+˜�8Q�Qytx|���Q��,��U���Y���:��)���!���y����1��]W�/UDw�Ir_΂8�F]��tb��V^7��=�RЧp������j<x����<x����<x����<x����<x�����'�_���} �  