VOC=/opt/voc/bin/voc

all:
		$(VOC) -s src/bbStrings.Mod
		$(VOC) -s src/w3cDStrings.Mod
		$(VOC) -s src/w3cStreams.Mod
		$(VOC) -s src/w3cErrorHandlers.Mod
		$(VOC) -s src/w3cObjects.Mod
		$(VOC) -s src/w3cJSON.Mod

clean:
		rm *.o
		rm *.c
		rm *.h
		rm *.sym
