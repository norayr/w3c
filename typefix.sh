sed -i 's/LONGINT/HUGEINT/g' *.Mod
sed -i 's/INTEGER/LONGINT/g' *.Mod
sed -i 's/SHORTINT/INTEGER/g' *.Mod
sed -i 's/BYTE/SHORTINT/g' *.Mod
