include $(GNUSTEP_MAKEFILES)/common.make

DEPENDENCIES = OgreKit

APP_NAME = Typewriter

Typewriter_OBJC_FILES = \
	main.m \
	Controller.m \
	TWTextView.m \
	TWDocument.m \
	TWCharacterPanel.m

Typewriter_GUI_LIBS += -lOgreKit -lScriptKit -lSourceCodeKit

Typewriter_LANGUAGES = \
	English

Typewriter_LOCALIZED_RESOURCE_FILES = \
	MainMenu.gorm \
	Document.gorm \
	CharacterPanel.gorm

Typewriter_RESOURCE_FILES = \
	Resources/Document-Text.tiff \
	Resources/Document-RichText.tiff \
	Resources/Typewriter.tiff

Typewriter_MAIN_MODEL_FILE = MainMenu.gorm
CC=clang

include $(GNUSTEP_MAKEFILES)/application.make
-include ../../../etoile.make
