VOC=/opt/voc/bin/voc
BLD=build

all:
		mkdir -p $(BLD)
		cd $(BLD) && $(VOC) -s ../src/bbStrings.Mod \
		../src/w3cDStrings.Mod \
		../src/w3cStreams.Mod \
		../src/w3cErrorHandlers.Mod \
		../src/w3cObjects.Mod \
		../src/w3cJSON.Mod

clean:
		rm $(BLD)/*.o
		rm $(BLD)/*.c
		rm $(BLD)/*.h
		rm $(BLD)/*.sym
