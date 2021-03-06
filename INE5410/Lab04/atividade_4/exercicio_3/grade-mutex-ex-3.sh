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
� �[ �=]W�H�y��ha,c�mB��c28	gp��������ؒW����c�܇{��>ݟ�?v��C�Z�!��9���wWWUWWWWW�Z1��s껗+���Ӏg}m�m��5��󨹺�du��X�|�h�V����o�R����		y��/*��V�'}�d�� D�Dn>��k��/Ov�/B�G��/�;��}=;�kk��G�qw,?��[9���s'�,��t������Vg�U�>x��YX��{�/:OJϻݝ����,��P}H�'�YZ&��N���Z�ǃA���#�O*�Y`8�6�%B��#��(��QD���!�	�{R�]�����I� �Ɨ�DԽH�0��/���{C���ш������"2�Q0v����243���/α<�iBۄ�ĸd��3<R%1��f��<hY��#[�$���^L��'���)��FI��y�����4��2�a�����OW���<��/�8�����O�H-�[%�qoI�(`W&g���ʋ"Ͽ L���h��h����P���S�;w�w�0)�ԃY�����A�K;@Ă��h<�m$FFa0
��|���\sv���t��+�Ǿ˚]и�~L��T,��~��ݷ�:���H�{	Ʀ��O?���/47�ЅNy���I��{��:=��Mp��W`c�7��8�ٌ���0��pi�R��KM˒D�,����Yuc|�FI�3p7��Ąլy]BY��":�b(���]�J�9��@鷗['�f�����H���Oea�Yw�t��jgX�cK�j�VU�5�U�Y��?d	䠪	�=��l��Z��
� ds3�]&ɆN�J�+y1�"�\..�<AuJ��l��6��y�ـ�ϣ���>9-?^n�O�5�(]�->K��`j��4rS��a�i��q�!Lr
���2Lu�g�6�8������jE���%�E+�ˍ����wV�lj��T�n�O��_9���AXOʖ/�.�O�<)����=ͮ�k�����>�y���h����[{�;['G�I�������K��m��ڃ�[Q��|w0��c���b�rS)C�K�� ە���۞���j`��K'��D��v�*�z:xj��c�X)����?gVgcfe+�`|�9�`% 1vc�U�M��7��`�މ�K�&FN�~�]�`s8,�?�M�Q%��!��<�{`-W��r��|�5y��wBc��
�>?����>m�z�>s�(�a�����c�-���\(��s�b��N�l\x`��?�(�&1c>3gE3��ȉ/۬����D#��;^�|w�[M�{t�ۥk}��`��Z5LOi�w�������r��&*M�q�a�a �T�-@y�;�ʜ�'�6� =�/��vͿ�ߣ��M\T�/K�5���S#��a~���GC�{!͔�t�|�=˒L]�;u�w,*�`��S�j�iQ'b֔K_7���������XVK�d>�b��#����j)��h,	����n���Dϊ-��4j���
`�#�ʉ9Ty��/L����l�K����w�7kú� Pw�Aϖ�ؿ����M�X�	���R~k4�y1�	�����t�Q����ې�S�����/�`g��U��45E3R�]��!�(K]�$Y���3�C����I��y(�� �A���Qv��s�x�	`ѷ	���vkC��~�;%:�7N����V��X3`���^[' �����^\2*���Zp5#ɀpȰ��g	���I�}�`���*i*��8���[Ro�������N��:�
�e����K�tJ��-T6���L�#�pj���&�o��he �-|��b�&��=a1KqF�B�  �ڝ�`]��	�j7��*f�F��Y4C����LR8+�e0!uz	���ܩ_6�H&��cPnU�ZV��+J�����qFv)B��b23m����ՙA���������8n�i��l�$�f�t�s�:��e^�����$��`���`w!�6�b����F�4�C�Q֍h1���F��w~�^X�)�@�0׻���MXv��&�%�,�{:wH39\�+�g@y��J��'�l�*�Χ�3꧍�aԖ:D���s��n�T8��<�kup�1��N�������������И�[}���Ï���}<i������h�#F��c����D/nc�-[�h�
���L��G����w��Ng���q/�W[��@�Z��>tF��2 x��=��*�N��qǶ_w�7����/����x���m�>��vZ��������G���d�c�'�����O���fs-;��k��{yL��Ó�Gݭ���Z���>��P�JfXx��-$?1=Ё�挾�V���o�Jc�zUu+%��rJNh�
C��*N�B�٫�I�x&�i3i2/�RM��Ql;1�<�=�c�� U@��J�ȟn�!��`\�~�)�����a1�(�t*E��{.�!�I���1l����)g6�2i�{tt,==|L��TpM�=+ݢ�A8�y�(��@�G����� Qٝ"Bb�-CW�TxRHJF�����W��<��rr*�)�`MT�1a���m�l��tds���+8�RL�79�zx��3i���ӿi�k�i.���'��}<�c�d�*��,0{�( ��pp4p<�:#��������=�B�HX���ğ���ȋ쐺�0�hZ��Uh��؏y������1�$V�8*� n�~망`��G�x橜�jK ��sL�b�XfINpDd3q!t�)��Bv��hǅ���T�=7�q�tN�ʕ����{w�d뿺Gm}Ŵah�7��z+2U��	�V��q���o�.��蹋a$0Ks�U�}{���Es��T�_řt'�gNf�=�i�΁:�<�,�>s��DqKw��T��H�J�4o����j�m�(�Rw��v����A���mr�z��0�����7d����g}S�<��N�[���������=>9:���@�h)���&q`�Fq�?�&�Z�y^���8"WXH�8"~@��� ���'7��/��x���3?��q� )�.�cW��o�!v���㭟��;D�k�a�,��Vd[�F+�M�Ӷ]�ޘ��N��r�4G6~[��M3� ��bk�p��u��Z��C.@,��"D̜.J�(�?\Wr�����)b[Q6IA;�̑�s����9�(g����R>�n�>:���ki�7���G�����y����D$ap��O�(G��dkt�,��B�Xu�����Q����}��Q���+���������ħ<�[��Kʧ���L	f�;q#��_�k�>�gu�R '�&|��\�b<���c �p�:W*���jp^^���E��%����Iך�Ȭ2�b��4ɓ�v❌�\i!���fXf�V�v��+N�:u�+�6�iK�<����	���u�dQ  NX���Sf���2�K����vz_CQ(�+�Bº��L2ʕ�M�,�BO�h|�3�r2Ȋ�Ƙp�t7~ ��΋X���X����OE,^��*c6a�!��7��F���S٣5t*�`�w��Z�0eB$�������.�`�b�E.Y	�7�4�7��5��P2��,L�łe}rsi;��|�T�#��)����0�;a��1�Öm`%�?NH��9ϵ"���lר�2�E�	�������i�Z��F�6d�
I�4J��j�%�*����S(Z!�uVCɓ�RuA"�g\�����K��-���"����F��s��G���ЋYIdLJ<K�v�3��OCd|'�+�5���ČbX��=K�C�=�`�2��S�9%o�z,�w]�r����٤-��	}NG_�X�o������x8��$���"P-`����[�	6-��T�����> P�X�	����o���9>3[tIzt@cZ�VYIB�mc���R�eXR S�8���fq)5mQtK`ل�[x��d/We Jfan_"��>�z�w�z�ő��  s6Ԩ<��3Z�Q�Ue[u�����e�g�elW�2����)#��Q���Y�Y*~�xaY�Q�o��ԏ�g��H��,B�b�8ps8u���=��o��l�Z��D1�=���%>]U�x��"�[���o�.���ʂHTM�3L��E�S�L!��t�0�W,U�
tg�:�ao(c���1h�Q�_�; u�L�B�����1�9=|���\�g����y!�H:WN\2o`�s�Z�S���"�Q��_K�,(�&90̾$`x�Yo)���4���	�����������ŊI�{�ëۨwJ�!�����	�D�'q�?�X����T�5���V�*~�*'��:�9�Α���8N:���0
|_9��:��;o�;�����4��M(�ً��0�<Dץ��%����E�agV!\�|NY}��7��ˊ�V��Z��u{�|��҃e���I��h�A�OB�B����T����S܌Oz�l1c�����;���f���,?c�7&M{1K�˵H�Ц|&%�h~9X
S�~��b�`�b`���,�gOaW-@�5��9���"ҦS(����=e֘��f��	�i�4����'O[���������ݷ_m��A��&��tBؤ�Yώ�2كC��&�wV��Hp8�Ԡ��P��"�ņZ�y����� ���i��
�Ǘ8���U��M����@d��
�O��հ�1�v��*��'I��v��,OY4��lτ���1 υ�,�3[���B�f}y�9��C,��:8��xHYo�&���	�y��9�$�j$�^�Pg�ë�g��/��������k<����L|q�p�c���*C+�$M?|�r]�-.L�7�񚴴gi$;�Gˤ5a����ڏ��$�..�؃��!��Y�1�x�ħhI�yYUvxs��?2YRI?�!a}Sq´���*�.e�LR������+�a�Ge��O���7g�n��R.}TͩF�<	�E[y@�wRW��B|.x�G�K��"� `]bVF��ŷ��2g�"�rBV۳
m?�.1�d�e�L"��w�������\�n̷��^�I*U���kȮ���8�d��E��u��bV���ޔ�V��h�Q<T[d�4����b6`���DIrV�۝XUA7�t]��{�xd2��N��3�(�Q{]�#��SL�TQ�An>���s���i�{l�:�zV����Rl�̚���9���"@�d��t9��{?�3����j���'k����>���+�F�z��Y�/��)�M�8�-A��C���_�O_�tFap:Cĥ|�ۖ��v0�_��������d���u~K�����&^�Dd��)�#�
Ȳ���U����:?�!AṠ>��Vq�#o�<�o̑����OڲC���R!�y��+�2d�JvcL6*�6�ޑ�.hA7R)�O>�'-�%���g�ã�G[�콃����� �(-�_d,<i������i5�"��Ӝ�I?�ſ�Xn���/?�귔�3�h�%h������RP���p�ڟ�1����FwuĴ��j3���������<�{�����)�J�����1��~R��@��0���aN�^��T���Q%9� O"�z�7W���%v��^q�����?���_��N 4�E�7��D�2yae�:aD�ݹj?]����p�2&O�q)��c�[�U���Z����^ÿ����lB�os%�� �!kWo�gj>L
���D��ZJJ�S�
��՚��fj�3�(:�!A�=�`�7�@�V5H�N�<���������DÓk-yg�L��;��s��&29�Z
,Sw��b2�ګ׋I��W2m�3����w��_ϻ�!���Ce�b��dg�"|y�8���R��ev�nʑf|f�ͭ��؏�'�@7#��+���Α_���)<�����j���2R�����;d5G(~f_�+�n�aw4�#|y�g��B_����^$-����x�y�θ�L]���������t ���.�R�)�_s�i���I��p��<����|o�O�L��
;�GǢr�pzC�O��d��N��Y��Z���y�Ff��]�N<�)��?Ĉ��ǽ�驅F��=S#y��7�v?���jBx��w�A����HU�{g�� ��bS�d���0���J��V3{&E]� �T����?@���I�����=�)�������'��{y���{W�۶D��X�
 �"� =�UQ�v��Zn�^�ȕLG+�KRE�o|*j����^����.IQ���@�܏ٙ73;��vrt6W���~-�������XF4.�&�U����79��+-���7痧�1��)��Q�?e�6Uf��M�j�Q`�}�3إ���-�A��F�#ԂsA'�n1Qzn��H�>W�S$��Uj$"K�>�.*f'�٬BA�D+�������*���y�UJb��Rv��g�ǖt���S�	��ݎ�'��ф_6Z�sY��X��D��}pssV�/������%&��v��}ԽͲ�h8$=�X?c����ʆ�$�PF[�U��<K��s��7��1��C�䪔��S����	�\��1��U4�n"'�P�h&S�ʛ�Yú�������cy���g�n�WtJ��A�	�`Fax���H7򌃃�������2���ѰGJ��}���O7)�3��X�:�Y�G|?2In���5n�M��L`Sv����N_�8a"���<��P��x$���+H��eѿS_�����3��ϳ�� ����0���s?�܅H�@J�$���BX{��4�?���ҏ�lZ����}9��\��^�2�0�Q�v'���H���$V=��h�"��.�n/E���#�*��������뾓������VA��b(�*6	��&�����X��o4��I-�����T�F�ܫ[hp��K��(��[��Yl<�nDQo�%��!���k��I���O�E��2���&�yAo�0��lL@�s ��6����u�۫E,TI��!�$$#S���H,s �����x"����/�s�+U�J�������$�n�Ƹ���u�u�=�U��)��M1��8|�
pH�;,��}��臘���[��ް>���KY����)�Evx�]S/a-:P�l�A���y{�ص�,��s��N�>"��&T��ͱ����1R�ه%i���*ÕQvO2��	�ֽ���:�w2�$ZQ��I�3BTwJ�� ��Wkـ^��;�������~,W�K���.	�* �� �틿�q`ː#ӂ�N� U���3�q���=a�"|Q���P�@��Fk��e��j�0?������c��{R�㵵9�g�2�:F5��+{���`��i��e���.�-���4xK]<fqh�f�ޡ%8T%p�R�<_��S�n�0��j�f���J�ķ��*������Zgj�����*�-`��O�ϧ?�F;%�gyJkʞ}���s�Z��T�^�A��x������O�m��tP gF6�U��lx��g��j�:��=T4\,���pnK[�Җ���-miK[�Җ���-m��� �i= �  