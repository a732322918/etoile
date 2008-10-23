/*
	ETContainer+Controller.h
	
	A generic controller layer interfaced with the layout item tree.
 
	Copyright (C) 2007 Quentin Mathe
 
	Author:  Quentin Mathe <qmathe@club-internet.fr>
	Date:  January 2007
 
	Redistribution and use in source and binary forms, with or without
	modification, are permitted provided that the following conditions are met:

	* Redistributions of source code must retain the above copyright notice,
	  this list of conditions and the following disclaimer.
	* Redistributions in binary form must reproduce the above copyright notice,
	  this list of conditions and the following disclaimer in the documentation
	  and/or other materials provided with the distribution.
	* Neither the name of the Etoile project nor the names of its contributors
	  may be used to endorse or promote products derived from this software
	  without specific prior written permission.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
	AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
	IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
	ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
	LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
	CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
	SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
	INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
	CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
	ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
	THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <EtoileUI/ETContainer.h>

// TODO: Turn this category into a standalone subclass of NSObjectController or
// NSController. 
// Implement sort descriptors and predicate-base filters for search (see 
// (NSObjectController and NSArrayController to get the idea).
// Think about the selection marker stuff and implement it if it makes senses.

/** ETController provides a generic controller layer, usually to be used a 
	replacement for both NSArrayController and NSTreeController. This reusable 
	controller fills the same purpose than the previously mentionned 
	NSController subclasses. The difference lies in the fact the tree structure 
	is already abstracted in the layout item tree, as such there is no need for 
	a special tree controller class with EtoileUI. The mediation with a 
	collection of model objects is also abstracted in ETLayoutItemGroup class, 
	whose instances play the role of lightweight mediators between View and 
	Model in MVC term, hence NSArrayController isn't really needed either.
	ETController extends the traditional facilities of NSController subclasses 
	by allowing to make a distinction between Object class and Group class 
	(leaf vs branches) as very often needed by applications in the Object 
	Manager style (see also CoreObject) at both UI and model levels. 
	For the UI, you can specify items templates to be cloned when a new element 
	has to be inserted/added. On the model side, you can specify the class of 
	the model objects to be instantiated.
	WARNING: the following part of the overview is work-in-progress, it may not 
	be exactly accurate or entirely implemented.
	This whole facility can be used at any levels of the UI. For example, for  
	supporting multiple windows in a file manager, you can create an 
	ETLayoutItemGroup instance, that encapsulates a layout item tree which is 
	the file manager UI. Then by simply setting this item group as an item group 
	template on the window layer, and wiring File->New Window... to -add: 
	action of this controller, new file manager windows will be created when 
	New Window... is clicked in the menu. If you want your file managers to 
	automatically open on a default directory, a model class can be set on the 
	on the controller (-setGroupClass:) or alternatively a model instance can be 
	set on the template item group (by calling -[ETLayoutItem setRepresentedObject:]).
	This ability to clone entire UI is detailed in -deepCopy of ETLayoutItem 
	class and subclasses.
	When a controller is set, it's very important to ensure its layout item is 
	a base item, otherwise the wrong template items may be look up in the 
	ancestor layout item instead of using the one declared in the controller 
	bound to the container. 
	ETController directly sorts object of the content and doesn't maintain 
	arranged objects as a collection distinct from the content. */
@interface ETContainer (ETController)

- (id) content;

/** The content must be either an ETContainer or ETLayoutItemGroup instance to 
	be valid, otherwise an invalid argument exception is raised. */
//- (void) setContent: (id <ETCollection, ETMutableCollection>)content;
//- (id) arrangedObjects;

- (ETLayoutItem *) templateItem;
- (void) setTemplateItem: (ETLayoutItem *)template;
- (ETLayoutItemGroup *) templateItemGroup;
- (void) setTemplateItemGroup: (ETLayoutItemGroup *)template;
- (Class) objectClass;
- (void) setObjectClass: (Class)modelClass;
- (Class) groupClass;
- (void) setGroupClass: (Class)modelClass;

- (id) newObject;
- (id) newGroup;
- (void) add: (id)sender;
- (void) addGroup: (id)sender;
- (void) insert: (id)sender;
- (void) insertGroup: (id)sender;
- (void) remove: (id)sender;

- (unsigned int) insertionIndex;

//- (NSArray *) sortDescriptors;
//- (void) setSortDescriptors: (NSArray *)sortDescriptors;
//- (void) rearrangeObjects;
//- (void) commitEditing;

@end