ETOILE_CORE_MODULE = YES

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Azalea

Azalea_SUBPROJECTS = \
	render

Azalea_OBJC_FILES = \
	AZApplication.m \
	AZClient.m \
	AZClientManager.m \
	AZClient+GNUstep.m \
	AZClient+Place.m \
	AZClient+Resist.m \
	AZDebug.m \
	AZEventHandler.m \
	AZFocusManager.m \
	AZFrame.m \
	AZFrame+Render.m \
	AZGroup.m \
	AZKeyboardHandler.m \
	AZKeyTree.m \
	AZMainLoop.m \
	AZMouseHandler.m \
	AZMoveResizeHandler.m \
	AZPopUp.m \
	AZScreen.m \
	AZStacking.m \
	AZStartupHandler.m \
	action.m \
	config.m \
	extensions.m \
	grab.m \
	openbox.m \
	parse.m \
	prop.m \
	session.m \
	translate.m \
	window.m 

Azalea_RESOURCE_FILES = \
	Resources/openbox \
	Resources/themes

#ADDITIONAL_=-DDEBUG=1

Azalea_LDFLAGS = -lXWindowServerKit

ADDITIONAL_INCLUDE_DIRS += `pkg-config --cflags freetype2` `pkg-config --cflags libxml-2.0` `pkg-config --cflags fontconfig` -I..

ADDITIONAL_CPPFLAGS += -DPACKAGE_VERSION=\"3.3-rc2\" -DPACKAGE_BUGREPORT=\"http://bugzilla.icculus.org\" -DSTDC_HEADERS=1 -DHAVE_SYS_TYPES_H=1 -DHAVE_SYS_STAT_H=1 -DHAVE_STDLIB_H=1 -DHAVE_STRING_H=1 -DHAVE_MEMORY_H=1 -DHAVE_STRINGS_H=1 -DHAVE_INTTYPES_H=1 -DHAVE_STDINT_H=1 -DHAVE_UNISTD_H=1 -DHAVE_DLFCN_H=1 -DHAVE_CTYPE_H=1 -DHAVE_FCNTL_H=1 -DHAVE_LOCALE_H=1 -DHAVE_SIGNAL_H=1 -DHAVE_STRING_H=1 -DHAVE_STDIO_H=1 -DHAVE_STDLIB_H=1 -DHAVE_UNISTD_H=1 -DHAVE_SYS_STAT_H=1 -DHAVE_SYS_SELECT_H=1 -DHAVE_SYS_TIME_H=1 -DHAVE_SYS_WAIT_H=1 

ADDITIONAL_LIB_DIRS += `pkg-config --libs freetype2` `pkg-config --libs libxml-2.0` `pkg-config --libs fontconfig` 

# Xwindow
ADDITIONAL_CPPFLAGS += -DHAVE_LIBX11=1 
ADDITIONAL_INCLUDE_DIRS += -I/usr/X11R6/include
ADDITIONAL_LIB_DIRS += -L/usr/X11R6/lib -lX11 -lXft
#ADDITIONAL_CPPFLAGS += -DUSE_XCURSOR=1
#ADDITIONAL_LIB_DIRS += -lXcursor

# Startup Notification
#ADDITIONAL_CPPFLAGS += -DUSE_LIBSN=1
#ADDITIONAL_INCLUDE_DIRS += `pkg-config --cflags libstartup-notification-1.0`
#ADDITIONAL_LIB_DIRS += `pkg-config --libs libstartup-notification-1.0`

# Xwindow extra (optional)
#ADDITIONAL_CPPFLAGS += -DXKB=1 -DXRANDR=1 -DSHAPE=1
#ADDITIONAL_LIB_DIRS += -lXext -lXrender -lXrandr

# Session Manager (optional)
#ADDITIONAL_CPPFLAGS += -DHAVE_X11_SM_SMLIB_H=1 -DUSE_SM=1
#ADDITIONAL_LIB_DIRS += -lSM -lICE

# Xinerama (optional)
#ADDITIONAL_CPPFLAGS += -DXINERAMA=1 
#ADDITIONAL_LIB_DIRS += -lXinerama

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/application.make
include $(GNUSTEP_MAKEFILES)/aggregate.make
-include ../../../etoile.make
