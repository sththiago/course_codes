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
� 菖[ �:	t��Ex�<��G.i(	4i��TZZZڔ�۲ٖ8M&��d&�L�����l
�Mx�,�(�V���������M,��ﻳ$�6X�����9紓���o��z�/R��(*�w��ኋ��wS\l���\a&�%&66:N7�c��a(��c)p�x��
#�T������O/���˺���
~��[bc�\�?�j��.�tP�R�����?.����ƚ��P��c������w�*���B�/"�JKԚ�4�ܔD��H������H?lC�2&jc�t�5m@J��Dm,����*�TY�� Q�$��݄���hiu<5iE���`	�x7Ey�V��^��AI~o!G�ń�e(�v"�- �PD1����H3�����%�	��b}B$�x/ő��E��σ�����FLɫ(��p#��d!�m�n�q��\���U$P2�jU���4�4���E$���E4e��LX&�p��@4��h��Ź(�N�X�o�4��>}b���?�R�?10;%�j���Àbeҳ�����`�~8*h�kCi����y}؞��$���p�����������0��1���|8O��x�������LH|�(��l��r����e�^^�77PvG�݀?��c��4%�,#P��tzT`�eچ$ju.���Z�F����5�k@3vy;0cp"28�᱈"8ښ�#zelb��(��1��[3�DI�1`o�N���6��
��,䍉/���
`DJj=wMU0���t��Ǹ)7O5�G(5R��@�s����)��&�:jXvbt i��9���h1J����"[AP��P5�A�� `X�
�n�7�Am&��h��F���կ�^�!JJj$����`Z�L�A_���!����$����	`��%��*�ȋ�*��N���a4;�5�H�4A���T����P(��+b,NXbʁ�Y89�D�puR�� �0hu�]���2������QQ��zJ

�td�����t�R��|���D����� ����X���ĥ��v2U�;��kp�}19P��GL@��Q*�jV�اQ9ű��F�#��aNz!>)2�)��j��q>
9}4���v�En���Nq�?ҩ2���v���T�ͪ�u���M�����4�j�����<���t��0�t`�C����Q.��pd�� �Wh5��D�x�Cz�X(;T���$_ �*3�ti"�D(R�R�>�%9R���ĲXk�2W�`��A\�� W�_Õ%�+KW�;ȕ%�+����H�����.t	��A�I4l�:D7@�r"W_�E-�&AͷjQ@cBі�_6�;(���̛�4�h�w�I��g�J'�M��;zGB�"*e��{��R���l�x���Rƫ���DT?�[���d�w5Q)���S��X��z�ԡ�y{�o�.H�� �Q�W6��?7��~2L`n��:X�W�RZ���c��@�ӥ26"���e�F�q�wk���t��i�r�g����4����������3"�s��X�Fr�"��By�L�X�0��� ��n/)!��ˈ"�DFJ�-ۚ2dXJnމ����p�q�d��ͦh�P4A�)�O���Q=_�$�0�$�(��R�*)�]�0�4cw�@�~��pӅƢ��1�m8�������aF������O�W/�P"m�H�<Q�3$��r��{���,z(O	:i8EG"�J�@ȻJLD&	7���Z�lY��EZ���"��}�*�����BU���)�W((�{�"N���RF-"wBO���e�ؘ F8Ї�ͅX�Ы�e��Na:m�H`�2���-���4���ԑi��r�*>�D�������dX���xr	ȌCX��iR�6�)V��C1�5��K����x�����5܆�	"q/�#��xh7x��������ݔqP݃qJ^���$��ƒ2:N�)�*��46�N��:XmলV50EQ�߶�z��F;_�h�^������;lxn�F��o�,�7A�̀*m޴�!;n�tX���bRr2l9YóS��4���Q�]o����B�ucqEĠ5��������0|L(�؄(�!u+*�/'7%;���؞zݠ=�<XЧ@1<�M 
�(V����De����V*ϗ��Ph���1:c/�.ߨ�W���Jd�|����U^YXn�,+���ڨ|.���\��Cn�K�P�/*e�b���'m�rH#��Kg�� ����(�S`����b}nd��"pCX�Czbx&^^[vV�!!ڕ
D�����)����l7i�I?�؆�(��n%��'D^��'m�{BE�^AI5cQ8*��^��`�^��S��(B܁I)ai$�$/��B��a�16=yT�z� cXn<���B ��xēN*�?�	�/�(�gc�y���r@���DPF�Pk�Q셋(h_���#�&��䢂���ȰM��1 [��Ф:����!���Ag����:�}�|�k�c9dg���qЃ\~܂�8�#&���)!���\q����GQ�,��.D�<�fC�YP�8]�"�݈�$��vq6��o�f��=$�4�^�C�9� c��<|2��|B$g�Ļp,,i	�*�d��en
[��Cv^>�(���e�(�����Zr*|!i6Ƃs��a[(/s�6T������V\e����oA��+��q�Hup)��kb�;�U��	�^�ME�i(	C!��d0��B��b��
��,BY���_�y0�)f�R&P �t�2OɌr4̅(NA-	)���W�]�x�2�I^���_���@.�-5q����I��x�2yA�Qb�?�DB�،� yP�� Cp��D�P~ӌT�١�*,�q�;
>ZwS.Z0 b���	����w����2�oa����ܻ��1��(�mhJjVN�F/�=!�fBn��B���:����k�� �.͕E�%�N��@E%����Z�}P� ��4�d} ��6��"9=h��l,�ݖ�~ޥF&5����
������v���?0G�,r@Q��R���Z������ٿ-E}  .A1�f˵���f�f��e�f�l=�\��_?_�#���k)��B�O0��wi��͂:Z�h���hȚ<�*H��P�|\!ai<DSe��PM�F�&K�(啸����[��k�q��f�??�Ψ>�E��|��v�.�-e��B��<D�9��7u/���=%6I_��c�8�I[�&�$n�2z�2DF���D��W��	�vjiPV&a�*�Ҟ�����!1K�g?�^q�,5Aef�X��~�dd�V�|�M�E���Nҿ�E�Ų�~�ʔA��IѤv�;�T�����3�ZJ>���6N.��9�W[�j�ĆN��&By+����a�f��k~6�x�7.��~i\k�	�:�-����5�҂�|��Cڑ�yv�4�����Ώ�Xt����ls������7x����]�-�;�_ٲe˪-��K�95��橍?�����g����;�t��ʉ�kJ��N�p����ႉF�?�~<a����3���~6�q��r�w�~�x��u����|#�����c^}�Ʈ殴oF>����n�ŉu��;w�~V��/�~g��]���	�����[Wn;p�LTiqEU՞�u�=?��=JO_5q}���:�|T���:������77Vo�Z��3k����,�X�f��/�-2���%n�������5t�����阩[8���R������&?���=y���/io�;��?Å5+R�ӦuJz��bͅ3���S��?s��Jk���&�Yi�};{�
ǉ]������~����VkN���O��p�+i��7��wk����s���k�������=pӆ��[b��.��x�v̶����'^�1��MN��1
ku�Xǉ��]Y�N�o���ƺ��[_�[?k��������~��ǹ]K&��n�ڹq�yˡ�dyZ�,��;�L�����dR���}���æZ��)u��g��}����힧�޷`��K�v���+����W�za��Vo�:&ܷ�ݩ�3O���⑊S��j�X��S�u�¥��vۘ[=f=P�&�Om��7~�|��O��oKv]q��tz֠o̻P�D|��
�x�/�|�>?n���.���Ͽf�|���[֝���	Ͻp���Cqo~��H��Fe�Z<y����;^x��3�|Z��x�}��OF��2������jl�����jɎ��s�?,���Gu�X����ьn-��uj���vf��vϖ�+Km��G�7�J���W�pa���̈�I�g=��<S?�����c;��yu��ӱ��W2�����Q'�7�[˽��"��E���cb"~�~��5��7�V(x�J�ڨ���=˖�{���T[����:Ne�ss���uuMn�ٕ�-3죘��mÆ�n�8��jR~������K�?�j�g簽c���q׸u�_<�9��Ū��>�`�O�3���Y1�������^��y���z��9	�Ӆ!��?$��^��b�G�O���=u9jSAE�Y�m��a��W�^��^�MÌ�Lo�w�yoMK�;4��]�k�%���Eƾ�jr�.cN���*W���$|���1���h��G�^����٪�>���t�������,����sW:�^_�r��Sӟ�e�K��Tv~�E��YK��qc�����r�~�������m���|��׮.����8{�6u�=��lt�����7]Ȫ��o�.����ŉ��W?�v���b�����x���n9����������Q1��V����]�ti���������;��6��B�u����
��`���<Kŉ�N��'�k_�f�+U����rέ'�~����W}��[7�뇪��&~�k劄��s}s|���kGJ�}���w���Ҭ˃E��O��Lk�㉭K�Է�����3\��e�i�g�{��&=��̽�V^{4����g��Mw=�������+��1�g���-6\<ý��ǳ>\�ڔ�i�/�K��U�7�~����aǆ.�f�K��2=�����?�Ī6Lm���6}0��t��ct�2�G���_z��O_��z\��b����JF.�1`\��6��7;�\	��<{b��D��$Ml�ؚxb۶m��Ķ'���y_�۽�Wwq��ݜ���]՛�ͯg�T��tX������N|t �b�����Z���v�0� �Q�yǤd��	�N6��{eJȏK����&�|����~'��Y��6O�j��灁9on��|F�ٰ�Z�.�!�RR��f�&��A���
�4GF��ȋ���Hi#�W~�5u^�)�z�����{1������1倝�[&-�wA̪��8k��WW#�^����ǿb!"���Yh|������ e�f<��K(C|����hC{wy�,��KϬ)��� �6�⭪�d�j��ꮚ\�XJ({�v�l��i�:w|GB���E��FGr�x��*����}<��9;�G���Q���=&l��,�P�Z������x1VC��'����䊠`�*g�ؙ�s��-�(�j����n#=�b}�#�Y:-q��%��O�J�b�0E�L���+���)�,��x�;�9y8��nP%ӥG	"jZ�:��Vw\Vġ��?g͹&��QB
�:iRm�*�����w�^�|�	�K
8Ҷ��цCu�tC��S��ξ���Yɖd�ȗ�rG>���2����+q�,�/�5� GF�����7�uK��.Kb�}����>c����~�<l�
3�,!y}y��([ �(#�vB1�t����5^g
��1y��[nm�����T"����R_��+Sn��䇥�d���W�5��d�+TF�l�]|&�PD���	6%�Ӟ��8��d����d��5��j����Kj�fJyq�����?G1�D}NM�<^�#�����t[�!Gas���v+� ң����2.��PI��C�iH1�A/�(�``/�c��'�B�1n��Z��eꖟ
���c*�(�	w�b�]`�s���c�x(���FxQb�!T�?O�s�����ǉ�1|�pX~��p��Zk�����.s૮�scښ'�Xvf�	����1gV�,�|\p��s�;>���z�l8�<���8�L^wm_��A���7�G�?�]I�Lk�/�c\���/N��C�FD{��UT\�%�2<C2�*bd��u�ǘ������q�}gN�_֩r����f5&�gV�Y��R��݄7�(����/*��Ru'�v����|2�4�8=qi�7|��붉�	�j@��F� �����:�Dm�+�ǃ�1kv/�	a�C�Y�����(f��᥷篮��1�ŗ5����:qc`�����k��M#Cd�(Y^�t��F1���k�u�0�Ӈ�i2��\��+�P��aï�o?�3�?��������|�׊��8�M��66i\�4r��sh�d��`�S7����p��!|���;V��޳Y�B�c=M��>B|���{Z=�D�1�]�F/�6"�~g���+Nb\f��A��U��cs/�ܛu"+#���i&<��-a���DSFA0�@('�ד�cT��|���I�qG��'�����􇈐�F��
VU=��� <6:6��Кm��Ȃ�5%��^�b�h��� �b�	��Y��p"�����:φ�g�����K��&_�/"�0G�g�j=���/�Z��!U��D	t�]`��S׿O�v��:����?��c7�(���
�����SM`ٝ��ʘ�j=�_��[v�p2t<��7P����o�m��m��s�Nq�wp����I"�<�!l+; Zg����ߧ�PG��J� u��*�6���Ps�����f|Ez�{�󾲣ᚆ&��k�y)^�I��_������̍]ϝ�=��bq���_=3P�ON��T�^lSv�);2uZ��p��̰ߐX��b���aE��)܆Г���R��I�R��a<gJ${-4�����GjSw���/�g�[��y�IBAEEL,p����Ȯ=�G���3�\�F/jQ�D҅%��YF��f��H1����H]Sy�C�[-���fՠ��S�.�fZLxC8lH,�<3��g�)f>N��ڭT������.����q�2{J���}������D��p+�����m1�P鶉u�o`�b����:8w"��I���D�˫���>����̶Ҙ�$���g����f>mC��Q��MI�4�N�ǫ�qi���~^%/j/��(e~�^�#��6i�Bޢ�a����+�6*|vb��8�|���'�qC(��R�̵Խ4]� �3Mգ�^>��b�-��}�F_���F�F��(�<ƒk�V3Q ��T�!�'�'KAAP����i�q��w���(�`*��;������3�U�Y�,BL�m��LdZ�7tA~�^4찑�N�L�
sk�@��S�H�/���bY�%��D�����fF�VFh�|I52R�� ���_b��a����Hm�̤vr�G�No��!T�'��J~W�r��˃�e�z��7�d܌�ڦ�c�����%^�|څ�tm�}$��d�v���⒭�$����Z�e��ߧ��l���4Jf/!ݭ��u�d=y�+��i:�E��}d�G���)�V`��)�%��'��5�eE5,���&�[l�956�"���r�d"�ϟ�K{Wcd��^��"��y�u�����bk�Q�.&�=��e��V,1܍��;69�J�L���!��Iݣ�7�_����e���'���1+�{}y�'��wG��+���7��� ���B�)�
�0�g�扄�ӳ��2s5�h�����<	,DٰM��F�%��+�	gɚ�y��ߺ�\}�a\d���Y�=�
�:����9+Las$J�ւ�r7M�J;4�K�2�>�Ѫ,p~/�w9i)�2ɏ�s��ľo+UdjDl-�}���0�d���ɋ��\p\�,����D���uR2`q����t*��P(��U��!N����Д����Z>���2m�J���ޑ���P/op��"ޯB/��:V~�v��[���ѻ�!P���'�v�njH���$�FCڟ���	����T���Ѵ�3����Ӹ�D�au��"�(���"��ݘ���/4�5d�䉕L�3:��S�]������,��|>!��kߊ-:��+"o���i2o\���J�+4"�ܪ�Ρy I�Ue���'��pk�U+�Ɩv���F�JC�[��(����H3�JrbF5
�җf�1��S(m-���c���:`�d0��99.-7`����Ư�k�����[�A 5�=�%)mLK�
� �@㇤|���h�-�G�	d�҆����o͔���씳��I�|1�+�$% }*Z�깚�%{۵-���w\��zM�!��E���y�����Jhz.S�pӠ��Og��N��������W*e�һ��:=�Z�DA��r���ݝ I4dl�����! �1��=��͓o��o�6L�GS�2�*T#ɞE~���7���x�� k�����3J75��H\��*VB���D-�)R�l��_Ö0�Y/Φnk�o[��L�]v�R�	W_n�h�V��HU(W�ɓ����n�Q�qH7G2����ZL�e��ϒd��ز�F^���$a��Z.T�@㞭?Ҙ5`u�L����	2/��H³Mծ�{㓾�hF%Wa���!&�����T}O���KVN)Ch�y[6{�Y���a�)��L2�N��󇂇�h�u�w�a�J����W��>|/�Q�ce]ݵx6���3tI����V	�=�������W+.�D�8����svo�[�x��k���x��@t"=,'%��Er��@� ��o���.r2&{��-�r�s�[b��u�
OB@�ׁ'*>5���9�����JAY)?H��Z��<��H�CO���U0񭩞MֺՑ�>a\/]��
Էn��	��=���F=�(��]:7T&�8���{]z���������Ӿz�j�ɥ�1_:Y�Wё��sl��J\�-�҆�T��)�5Iǣ��i��ǯ�!!��$������8^��W�A�����r`r�����t��ߋ/O�ʸ?�p�X#
=Z%ZF�$��+l"�(тOkS����@/U&N��kX����-�l0�َ��O��Zî7��x�{���������\��懷?�hb�b�TSSCx�_�$�x�둼�҈���7+�����yJ�*�hj�y}�&��PzDHe`z<��d�'��� Z����;�lz��-ԕ\�?��+�k%�b�L��tO��x@X��d�o<g��RQ�2�M�X�Uv*B�v����)�O��H.�j�U��{2��E1PG�!7h�|�xS�3��]"s��1�O�K��3p�djw�g�'C�j_c�_Q���@?�?�_�<A*�o���Ry�O����^��/<�o�ӕ��Bh����}� �w+N����m&#D3��U�΀����@#�0?�a�.#z��d73�6�Z�% �U��r�v��ZR���\@�A?i�!� "�d4�d���eSyy�lw���P3����;��S�Z�s�>��\Nr̭��=�!��R�:�Q{a�{uB��Ȯ��}(�z�s�ǭ��:�]v�ȥG{�9�Յ���h>����t��K����+�����Q{ޣ�mg��yXy�e(�IG�%�U�ȗ�/ɝ���n����-�t&*����z��H&m�@��ÈUI�mnM�����$ o�G�6�C��p��Xh@r͑s��4�N���`}�:���%;�1����J�S�51q�{�-O���b�ڵ�n^���V�}��٪b޿�����0_y\�S@����<��,��{|D����h�V��HL�<�Cj���T*���>y��M'�i� N�+��`,4�i/;<���$5��
�	�m(3��s�0�����˷H>i��0��r�1\�K������zJε���)��6�Ѯ�}ߝ��:u�P��ߩ�b�PP�Pw���)�;�����n���y�.9Ps����T�x��(��̦���:��l'������߬M_[K_[��O?�A�0�7��PKr�J�a{+�ni�M�~��m���̚. 2�w��j%�v���N�>��ߘ�A�����������i�-�������/��0�[�!Öx�PN`U~���8J�fk^Zb�ۛ�0��u���x�x�ˋ~-�������w� ~�K��aR����gm���H���.�9�i�ٲ���!I�<�Zz|��=����L_/���J&t�V�;�7�Y;S����u�"��ʀ�aT�����Lp�&7`<�%��s�D]�9q�H�e��1s��©�)�Y�S��%2��ʑ��t��,O�9��${,���GEB����|�_dJ�Rh�19��3��ѽ��|�-w]�wDIwA^uM�śc;εY֮�?B-gO��GY):�U���G.��A�C!��R��Ѥ|�,�s�G���Km��7:~%�v��s�~�ԯ��7���2'.����~(\�0yo�����|���wC��^��?~��*[��
����A"��(]��#�H���Ƃ;��s�e��ܵ>r �er�{���e|�n"5�%��,ō>4�-�uFڣ�å%�&�p~@Z�81lU����f�tw�11����o���m���c)J]�Dv��&�A'ӿ��u�z|y��f��(â��,�c�*���\@t���ތ�Tz2��ZZr/�����������`���[�ޗ}O��o��������nl�z�B]n�Gwi�Q�''o	CK����������~�������в��Y,Ǻ��o���/��&&�`���*���u���N�R���}v*�X��:Pg�����ܛ̟��ƃEb#ܴ~�S���$�g4m~�ߡ�5�`��~K�y�ǓF���D?�D�rS-v5�Q
-9�^��$o�U��V�T�|r�z�Pd,yNLWT2P�
��Hs��3$���p����.!h����ɺ�yzZ��̓�@���2�``Ļ��e�M�����	oz��:�~ֵ��
���\�"���:��H�<��c�.���)��y�@gBF��=�r.ȧ�o�������q���ٸ�=i����oA`�uDk�0�ՒN��ePc�\���W!�*����#�A�r$�5?n RF�V��D���BL}GρE���e0�(�JR�ٮHmD����J��EOX�e��J޷�c�{��?�"s� ��Z�,ZP|B�n� +���^w�(�B<@sD:o��S������s_�]d��A������+�~Z�&�ŝS��%a�1�F�����G�*=2��7���H��=�{���}���������%{zt��[h7�Ӥ�)¡�7e?�r���k���d����S-X�f���??!��s;{^�N[u�F��d��fȚ�[�^�G�"����l����3Ӊ���;Q��Ԇ�@�G�u��k�`	p'^M���n&�g��.>�(L}�^r�F�k�1�<j�υA�վ���O�d�X������3��ؓ�d������=�|��/�����I���D�Ṽ�si��嵽����~�ϓS�%Q�Sy�m�ր����͸7�N9� ���ff�w�|�H�E�a��F��옕�8wPٙ�����/�"�!��1H�৿�Rr^A�,�P��MNq;��I�rkN��n�L�5K8����/�D��Bm�%��9�T���MD|:\ȹW� ���s�`��ux���'Za�GN� �g~<�7�`V>vwn�#қ���ԭ�%6EyōԴ�� v+�g����"��rܪhNdS�p��yP�3w���gIB�	����hY؀�lv�K�Y@;������HZN���@IP-���׍k.�t��.	/�e�/*��Z��:q�z�o^O��z��?��#i�������ΩDxm���A8O�e�!�O)nT���z\��EB�۳�/@�}��!TH����pM�MU�X��4�a_�������V��#F_��b��Z#S`S��}��Ǜ�rĀ��p9���
ր�t�&������t����B���G�Y3\���1�Ƣ�au�����8�(��F��岣F6�e
ɤ%��sS�N�T\�"x$n��TWtz�}(X����4��6��'���Z�2����U>�^�C��|Sc�g���K>DVV�t8A<{�2i1��tp<ndl�I)�B	͘,�����aB�!���]�?�<8I�����܄���/�C���M�!F��)V\��_)\!:���'��lZ���j�\S+�5#DB��>u�N��F��"u�����ղ��-��n2eL�5&gq�RYl��\�8]��\o��B��"�Qၦ��qԕ�-U���s51A@'|�$Y&�5��Y!(��_y���r��1��-��o�k�����_�O.n�����w���`��?���O���O���O���O���O���O���O���O���O���O���O���O���O���O���O���O���O���O���O���O���O���O�����US6�3��B:���4Ԍ�[Y:����F�E���)�aE��E+��
���㛩o�.�H~Ф�Ή�Ȯ�7L8��0uߴ��e��02N,p/��X\�Q�T?�5����k�?&�iLd��e{j��2��t���Z�@r����f��C�E^�VN?6�?��vZ���=g��O��~�S�ǈ��)�����f�5Ww��Qu�d��\�H�<ue��㎦�~I
]�4�3P��%�\gY���D�+C|�Nlm%u���`�t�`N�5��&i\<h�vh_�
m_�����C�+MB���	b�5YcZ �U�4�3��iy�{��	�Xsư����\v�뒵�SFq�N�}:^�Aǖ)V|���$KSoz*��T�V�&$������/��bǉ��r�SQ��NM���#5����24�9�*I���D��T�ze�/�ϵ����Ǒ�O��+�:eʊ�̚0W��˸ ����x��X;�)���\Qj�ڴ������r#~)$�e:,�/Xkd���!\.���(L�Y��OR��%dPZ�hTC��ƒ������늷rg����	��s+�Q-��څm�}n���7Ҷ��l�t�����co��5�S��;�l��΋	�b�O>Ħn��*E�X[�U��d�����4���qx�X�G3�jƁ�ZrYZe[�ر�[ݽ��6���`@'���q�@4�~�G�{|a�l&����9� �YWS?�_��~�!��> �b�AV�'�X�����wW_Q?���DrH�aH	�A�1�PC��tI�#�*�!�0�� 1��2t�����Ywݵ�y���?��ڇN�p5��dב��W����TNƔ)���4Lj��e���o:Ad#oo4�M����!�nՐ�g�����ԇ�)��<�Q
<$�BNz�"�k�{�ӟnu[�@"[?7sf��a2�i�a��<������z�o]s���kYS�����J���)�.�ޅε2X��{ӯ��Ϸ]�����T���mʟ�i�����9 M�ZO^�9g���|E�q�%��q��|���ι���&�'u5�~��`Cr���������7h�`�{z)�)o�]��o�^ޟK��	�2�����S�VS�q�������L��۱:���G���/��ʥ,�ͺ�r����		��`�L�]��X�>��f�Kl���?�ey�ç��ꒂ��i�-��c�6R��t�W��~����v�UB��C���IRQ�e)5�I?�C��X�Eå�?jcI���'%��`�T�'1��E��������4��G�4�9$��*`(y���D�Q(kV��C�.ln-u�y���'�|'�����7�?�e�_��i�o�T��A���w�,WW+���]���tӓ�_�c�����몍���JFȷ3���#�q"٤u��S�Jhw#r����Vj�Fu���<�[���v-8y"��	��f8k�S5Z��#�C4:P^7A�{|Сeo<#Q��>!po��Vt���"Dѯ�O�������{��6�A����7�aΫ!1U%�+���v���,}�"���x.ɱѶ��j�1�-�`(\��u�ݝ1px �"������9):�(�ª� � �Gv�ɞ޽u�:}z:�Q�1��y�)�i�����g���U2��؄�%S�W�md_ߝs�:q��ț��������s��X8�e�������ӛ���<vO��<�����'<��Gف#��Mw�$k�G���M=��Z��ԭpy%�I(F���|9$q〗ہo7���L|woy�"]5�#]�9V�I����8i3�ؑH*$I�mekn�@�I�w�;U�������k�K��N�)E	�kd��)ʊ�Q;}�e��G���C����ǅL�ω�%l�fb���_�<��	+�Ql;��g�65�d��>�e�|	�_S.��%�e���]e6웂��d��Z�CɟŦҍ*z�K#��(���q.ɑy�ߤ��L����;Ȇ)��V9,]����P0o�$T	N]�b����D����n�+t���a�)WW���j]������g��U�u�����Sڍ����v��h�HU���]�n�j�Y�D�e�[3j�t�'q�)��+=�=�!�wl.� �٨��|�G��";�S�vQ~l-@�U�S��P6>?�E0�=�;�Y<���<G"ΎL��)�J���%)/�{#^ ����	2[�_d�Z�3@�D��^��р��-X �|!�n�}+�n�'餃|��=�T;\�{��I.u���Y����>yD��:!t%��B<�~���V
�Mzs(�������P�=UJn�#DK
��'��o$�r�"�ũ9���
�V?������^d7���Do�^�d���'Ԇ���ʇBM�di�:�@��H,)��,����D�����F�i*���q����uJF��/�B9�V�Y��2%�T(Sk�$N<�y�.�r�ް��n�s�e�ťl�=��OF����"A����zaЍ2���>֋��	���A�����y%[3�����zoc�ŏ�V!�2��9mO��M�)��1��/�N�9�
׭Is��Y��n�����=��Ǭ�$0Lr�1n�Q�a�Lz,hV�^xL�ų���4�\�N��<������y����Yڰ-��"h�p�Նˡ&�?��MG�;=_&�ȯK��!�Q�ٗ����W���wo�F�]hg��C�����#�X���7W����sP����BT��!ZPć��n;=y �T��
�'�{^/g�i�D���s��zzWԲ�Z�����c�ޭ��Q�2��(��gJ�P>Q��,H��Vu��]O݉�*T蝫��]�>ՆW��םPz.]�K-1 ����c%(p�� �����$߿n�^ü�3�'$U~�aى�p"�b��{�St�[����S���~QO��K�j(��(�^�=�~8�9#���V]ϋ/B<�G� �J�`ە�l1JJ�a��Z3��ɖ��T�/�w�%�^Q��{��yhg|st|��QR.���ٛ�n�U����7�6OI�9�H�ءG�rov�>���֎�P^��$���4���]ɤ��A�È�i��h���L������|��%WP�:��k�5�BT�<���(�7��*=�:�Ì7|���mW`('fÿ��_B�s"`���%�ҏcՠ�����d�~���F�_J#w�5!N�#x�kI?S�^������W�J�:��Ѫ�ɯ�p�,0&��\aq���Z������j'�X���5�e����"ǖ6���c`e�unҌC/^��GvE5f�Y�l�d��dn�+^���cΘ&~>�L޺���V���ۈ��ID�7��y�V�֊O}�xʁE�Ns����f2�j����}8}��I�X��
65��g�R��w
WP:J�(�}��v�І{�^A��#�*ڒ(/����Aꤶ��i�K�a�\�sU<��R%;�����T3Ag-��{��5��j^�l����ӟ�!��� NsYX~�F˧$`�q��N�mM��f�]���X���A0znҟ&UȄ��o��~K���itg���>�����%D��-)��G ��o���߀��7���o���߀��7���o���߀��7���o���߀��7���o���߀��7���o�����)�����;3���d�^��	Z<�۔���pjW�ʁ��J��� 3H�S�	B�/������c�a$t�D������ws7��D=��2�,�a�&o�z�"�ྛ)�}����ͱ��`��;��Pb=��t�p��Eh�N����Ȧћ� 8�&Ђ8���V�ֲ���ݣ�f�ΰ�p|9D`=aZ�Mr�� D��B�жx�`�@��c�J�P̰�"?߶��mQ���s��j!��� ��5�HdI��(+y�v�?e��.��lK6�+<�I@�:�~݀�����_;�%�����x�t�}���U��K���Q�yU����m�5���2�Y]�~+�bH��@��X���gN��.�.~zt��+�#`�|Z���!��x��(�v�15���l��P��e@gz�����و�u�
>z��Ŗ�u�ω�1��W�E��Ӟ9�p\A~<ب��9l0�f?"�!���_��hQ�F�K q����1�0T�ɥ�[f�-b�huA��w�� $C��C�I�Ac���ҟVk�;��¥�����ir�}�̱h���͝�/�W�'�R�y��C�978�v%lF��k�Py���u�bg�lRZכ���b��nL�^{���`A����"Ǥ4���%��;��n��<����E���V����[��F�'���299�2�1$���m7�	�����qPjj2�1�sj$
tQ�eMF�Ԯ����o�-�QG`��EG-}_1/&�ןe	~�C6�����	�_���-���6��F�����
=v��Vվt��"C���KaC�#A��JڴF��g�^q��̧�b��N���㐘�`�3dSA[޴��Qf�F,I������ߛ�)�����l�J%�g��	�So����=yE���h���w,O��z�H"|��A��ٍc~-X��S�X|�����Tw��\��QB؈P���i�����r����i�Vp��H�7?�R^�K?�s�0�2�w�
A���uR-��ބb-~�����=��G�?�������l��+e>��Gx���؂�ssnD���}yUa^[bWж��u\����B��J���Jd�햸�xM������K��\ً�J�ao�m6�֓D����ox���8P��P�k�I����亁��N���R������v���ބ��g�Qu��]���UF�/Os�J��"&39nH�z�q/�AAb.TEׁ��.�Va��BN~s����Vŝ	
ˉZK�d��޽�3�pg&�I.-����i�q��s9#sK*w�L�k!�ˈ�,zE�5���c!Z�L!�-#�G�\�qί�?8�s�������OЛ��j6�gꛦ��C6�ϙ�kհ�	�!�M��ֈ��DL��n��ƿ�ޭV��N�������{��#��>�	m�X��>��N�@P�r*����{b�8��ouR�`4�9B�WF�<�������H�r�t��L�ӻL�X�@#)�?;-��K�E]�|��Lb�^�n�:�ea�w�T��>���ۀrs4d3��v�e���{}�c<#)���&lƦ-f����3�}�B2{�-��Y�e�L�mG��(N�w���4��C���'Lk&��ɧ��Zݩ_1�l>�Kb]!�0� tD_��gvIW�D�NAi�@�k���%1���X-���scU�K;"�0�
�>ӑ��c�">�wn��]�-ˑy�׹���ֺ��צ�X�Zim���8p��)�lՀF�����x����)�=m(��Nk�#c�`Y��cEGҴT,~S�,RM���9Ll+����?d�n��ë�~�ד�^q�阎�ޖD�rև&şyۈ����4��`���T4��T�2O]O,���4}R�k���ֽg�o�8�ť�E��Xԧ�Э8_QV�e�@�lt�hBZ*�5�dm�Clv��8��*e<���C�łu&�h���"�ӏ�`3E��W��/��M�[�Q!��S9�_�lo�,�z�_��5+E��%�g�њ�:'��|{��1_r-����Gn'��\�K�D#-3}ђSu�6ŝC�p�������yS9��'��9�n�d>Q7R��qc8L�#W#�tE�Y��v�Z�}sց�w�Y�$���r~\0�s����B5Ҿ��d�^��A��ع�Bdu�7w|7���1�������l����i���Y�Ϩ�VT�2 c�M�y�fn5�w�s��Q��*�	j�G��b�Q����̀b���Y��������Jd1,����H��Az$�� l_�,9Vr�p���=��a|�-�3���[|؈�B�~`���_6���f�t�a�#?�wxz3�b��<;���k��_iC)}���dњK��LF#���K&#0sw�P5;��m�ڈ؎������4�uR^����Pw�E�-���<�Oȶ4���t�hA�
r��o������4<��)z�Α�ЪL&#�,x��R;�>���w�#f"y�{c�� _Y�����e�v������buL����xH�K��%5��"�~�~̩�J�#ާ�Y>Z���K�3��c��2� W��ES�7jȥww�p��ti����X���Q��5/�Nu���+j��v�������t��[®�9s.V�`ž��fc����bd\�:#��9%�,�x����S� ���Ȃ���'�Hga�����JZG�T6�Mi��a0�I��Ac�1t�������mvT�;]���<                        ���߹^�� �  