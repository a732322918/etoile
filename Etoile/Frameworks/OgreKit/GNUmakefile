include $(GNUSTEP_MAKEFILES)/common.make

ifeq ($(test), yes)
BUNDLE_NAME = OgreKit
else
FRAMEWORK_NAME = OgreKit
endif

OgreKit_VERSION = 1.2.1

-include GNUmakefile.headers

OgreKit_SUBPROJECTS = Source

OgreKit_LIBRARIES_DEPEND_UPON = $(GUI_LIBS) `onig-config --libs`

ifeq ($(FOUNDATION_LIB), apple)
ifeq ($(test), yes)
	OgreKit_OBJC_LIBS += -framework UnitKit
endif
else
ifeq ($(test), yes)
	OgreKit_LDFLAGS += -lUnitKit
endif
endif

ADDITIONAL_INCLUDE_DIRS += 
ADDITIONAL_CFLAGS += `onig-config --cflags`
ADDITIONAL_LIB_DIRS += `onig-config --libs`

-include GNUmakefile.preamble
ifeq ($(test), yes)
include $(GNUSTEP_MAKEFILES)/bundle.make
else
include $(GNUSTEP_MAKEFILES)/framework.make
endif

include $(GNUSTEP_MAKEFILES)/aggregate.make
-include ../../etoile.make
-include GNUmakefile.postamble

