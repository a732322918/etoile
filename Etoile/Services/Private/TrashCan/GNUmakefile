ETOILE_CORE_MODULE = YES

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = TrashCan

TrashCan_OBJC_FILES = \
	TrashInfo.m \
	TrashCanView.m \
	TrashCan.m \
	main.m 

TrashCan_RESOURCE_FILES = \
	TrashCan.tiff

ADDITIONAL_INCLUDE_DIRS += 

ADDITIONAL_LIB_DIRS += \
	-lXWindowServerKit 

ADDITIONAL_GUI_LIBS += 

include $(GNUSTEP_MAKEFILES)/application.make
-include ../../../etoile.make
