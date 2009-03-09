/*  <title>ETContainer</title>

	ETContainer.m
	
	<abstract>Description forthcoming.</abstract>
 
	Copyright (C) 2007 Quentin Mathe
 
	Author:  Quentin Mathe <qmathe@club-internet.fr>
	Date:  May 2007
 
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

#import <EtoileFoundation/NSIndexSet+Etoile.h>
#import <EtoileFoundation/NSIndexPath+Etoile.h>
#import "ETContainer.h"
#import "ETContainer+Controller.h"
#import "ETLayoutItem.h"
#import "ETLayoutItem+Factory.h"
#import "ETLayoutItem+Events.h"
#import "ETEvent.h"
#import "ETLayoutItemGroup.h"
#import "ETLayout.h"
#import "ETLayer.h"
#import "ETInspector.h"
#import "ETPickboard.h"
#import "NSObject+EtoileUI.h"
#import "NSView+Etoile.h"
#import "ETCompatibility.h"

NSString *ETLayoutItemPboardType = @"ETLayoutItemPboardType"; // FIXME: replace by UTI

@interface ETContainer (ETEventHandling)
- (void) mouseDoubleClick: (NSEvent *)event item: (ETLayoutItem *)item;
@end

@interface ETContainer (PackageVisibility)
- (int) checkSourceProtocolConformance;
- (BOOL) isScrollViewShown;
- (void) setShowsScrollView: (BOOL)scroll;
- (BOOL) hasScrollView;
- (void) setHasScrollView: (BOOL)scroll;
@end

@interface ETContainer (Private)
- (void) syncDisplayViewWithContainer;
- (NSInvocation *) invocationForSelector: (SEL)selector;
- (void) sendInvocationToDisplayView: (NSInvocation *)inv;
- (NSView *) layoutViewWithoutScrollView;
- (void) cacheScrollViewDecoratorItem: (ETLayoutItem *)decorator;
- (ETLayoutItem *) cachedScrollViewDecoratorItem;
- (ETLayoutItem *) createScrollViewDecoratorItem;
- (BOOL) doesSelectionContainsPoint: (NSPoint)point;
@end


@implementation ETContainer

- (id) initWithLayoutView: (NSView *)layoutView
{
	self = [self initWithFrame: [layoutView frame]];

	if (self != nil)
	{
		id existingSuperview = [layoutView superview];
		ETLayout *layout = [ETLayout layoutWithLayoutView: layoutView];
		
		if ([existingSuperview isContainer]) // existingSuperview must respond to -layoutItem
		{
		   [(ETContainer *)existingSuperview addItem: [self layoutItem]];
		}
		else // existingSuperview isn't a view-based node in a layout item tree
		{
		   [existingSuperview addSubview: self];
		}

		[self setLayout: layout]; // inject the initial view as a layout
	}
	
	return self;
}

/** <init /> Returns a new container instance that is bound to item. This layout 
     item becomes the abstract representation associated with the new container.
     A container plays the role of a concrete representation specific to the 
     underlying UI toolkit, for a collection of layout items.
     item should be an ETLayoutItemGroup instance in almost all cases.
     The returned container is created by default with a flexible height and 
     width, this autoresizingMask also holds for the layout item bound to it. 
    (see -[ETLayoutItem autoresizingMask]). */
- (id) initWithFrame: (NSRect)rect layoutItem: (ETLayoutItem *)item
{
	if (item != nil && [item isGroup] == NO)
	{
		[NSException raise: NSInvalidArgumentException format: @"Layout item "
			@"parameter %@ must be of class ETLayoutItemGroup for initializing "
			@"an ETContainer instance", item];
	}

	/* Before all, bind layout item group representing the container */

	ETLayoutItemGroup *itemGroup = (ETLayoutItemGroup *)item;
	
	if (itemGroup == nil)
		itemGroup = AUTORELEASE([[ETLayoutItemGroup alloc] init]);

	// NOTE: Very important to destroy ETView layout item to avoid any 
	// layout update in ETLayoutItem
	// -setView: -> -setDefaultFrame: -> -restoreDefaultFrame -> -setFrame:
	// then reentering ETContainer
	// -setFrameSize: -> -canUpdateLayout
	// and failing because [self layoutItem] returns ETLayoutItem instance
	// and not ETLayoutItemGroup instance; ETLayoutItem doesn't respond to
	// -canUpdateLayout...
	self = [super initWithFrame: rect layoutItem: itemGroup];
    
	if (self != nil)
    {
		[self setRepresentedPath: @"/"];
		_subviewHitTest = NO;
		_itemScale = 1.0;
		_dragAllowed = YES;
		_dropAllowed = YES;
		[self setShouldRemoveItemsAtPickTime: NO];
		[self setAllowsMultipleSelection: YES];
		[self setAllowsEmptySelection: YES];
		_prevInsertionIndicatorRect = NSZeroRect;
		_scrollViewDecorator = nil; /* First instance created by calling private method -setShowsScrollView: */
		
		[self registerForDraggedTypes: [NSArray arrayWithObjects:
			ETLayoutItemPboardType, nil]];
		[self setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    }
    
    return self;
}

- (id) initWithFrame: (NSRect)rect
{
	return [self initWithFrame: rect layoutItem: nil];
}

- (void) dealloc
{
	/* NOTE: _layoutView is a weak reference (we retain it indirectly as a 
	   subview though).
	   We are owned by our layout item which retains its layout which itself 
	   retains the layout view. Each time the layout is switched on -layoutItem, 
	   we must update _layoutView with -setLayoutView: otherwise the ivar might 
	   reference a freed object. See -[ETLayoutItemGroup setLayout:]. */
	DESTROY(_doubleClickedItem);
	DESTROY(_scrollViewDecorator);

    [super dealloc];
}

/* Archiving */

- (id) archiver: (NSKeyedArchiver *)archiver willEncodeObject: (id)object
{
	ETDebugLog(@"---- Will encode %@", object);
	
	/* Don't encode layout view and item views */
	if ([object isEqual: [self subviews]])
	{
		id archivableSubviews = [object mutableCopy];
		id itemViews = [[self items] valueForKey: @"displayView"];

		ETDebugLog(@"> Won't be encoded");	
		if ([self layoutView] != nil)	
			[archivableSubviews removeObject: [self layoutView]];
		[itemViews removeObjectsInArray: archivableSubviews];
		return archivableSubviews;
	}
		
	return object;
}

// TODO: Probably implement EtoileSerialize-based archiving (on Etoile only)
- (void) encodeWithCoder: (NSCoder *)coder
{
	if ([coder allowsKeyedCoding] == NO)
	{	
		[NSException raise: NSInvalidArgumentException format: @"ETContainer "
			@"only supports keyed archiving"];
	}

	/* We must disable the encoding of item subviews by catching it on 
	   -[ETView encodeWithCoder:] with call back -archiver:willEncodeObject: */
	[(NSKeyedArchiver *)coder setDelegate: self];
	[super encodeWithCoder: coder];

	/* Don't encode displayView, source, delegate and inspector.
	   NOTE: It could be useful to encode tham as late-bound objects though
	   like [coder encodeLateBoundObject: [self source] forKey: @"ETSource"]; */
	[coder encodeObject: [self scrollView] forKey: @"NSScrollView"];
	[coder encodeBool: [self isDisclosable] forKey: @"ETFlipped"];
	[coder encodeObject: [self representedPath] forKey: @"ETRepresentedPath"];
	[coder encodeBool: [self isHitTestEnabled] forKey: @"ETHitTestEnabled"];	
	[coder encodeObject: NSStringFromSelector([self doubleAction]) 
	          forKey: @"ETDoubleAction"];
	[coder encodeObject: [self target] forKey: @"ETTarget"];
	[coder encodeFloat: [self itemScaleFactor] forKey: @"ETItemScaleFactor"];

	[coder encodeBool: [self allowsEmptySelection] 
	           forKey: @"ETAllowsMultipleSelection"];
	[coder encodeBool: [self allowsEmptySelection] 
	           forKey: @"ETAllowsEmptySelection"];
	// FIXME: Replace encoding of allowsDragging and allowsDropping by
	// allowedDraggingTypes and allowedDroppingTypes
	[coder encodeBool: [self allowsDragging] forKey: @"ETAllowsDragging"];
	[coder encodeBool: [self allowsDropping] forKey: @"ETAllowsDropping"];
	[coder encodeBool: [self shouldRemoveItemsAtPickTime] 
	           forKey: @"ETShouldRemoveItemAtPickTime"];
			   
	[(NSKeyedArchiver *)coder setDelegate: nil];
}

- (id) initWithCoder: (NSCoder *)coder
{
	self = [super initWithCoder: coder];
	
	if ([coder allowsKeyedCoding] == NO)
	{	
		[NSException raise: NSInvalidArgumentException format: @"ETView only "
			@"supports keyed unarchiving"];
		return nil;
	}
	
	// FIXME: We need to write -setScrollView: or may be come up with some other 
	// way to reconstruct the scroll view decorator
	//[self setScrollView: [coder decodeObjectForKey: @"NSScrollView"]];
	[self setFlipped: [coder decodeBoolForKey: @"ETFlipped"]];
	[self setRepresentedPath: [coder decodeObjectForKey: @"ETRepresentedPath"]];
	[self setEnablesHitTest: [coder decodeBoolForKey: @"ETHitTestEnabled"]];	
	[self setDoubleAction: 
		NSSelectorFromString([coder decodeObjectForKey: @"ETDoubleAction"])];
	[self setTarget: [coder decodeObjectForKey: @"ETTarget"]];
	[self setItemScaleFactor: [coder decodeFloatForKey: @"ETItemScaleFactor"]];

	[self setAllowsMultipleSelection: 
		[coder decodeBoolForKey: @"ETAllowsMultipleSelection"]];
	[self setAllowsEmptySelection: 
		[coder decodeBoolForKey: @"ETAllowsEmptySelection"]];
	[self setAllowsDragging: [coder decodeBoolForKey: @"ETAllowsDragging"]];
	[self setAllowsDropping: [coder decodeBoolForKey: @"ETAllowsDropping"]];
	[self setShouldRemoveItemsAtPickTime: 
		[coder decodeBoolForKey: @"ETShouldRemoveItemAtPickTime"]];

	return self;
}

// TODO: Finish to implement once ETContainer is cleaned.
// If we decide to use EtoileSerialize here, we also have to update 
// -[NSView(Etoile) copyWithZone:].
- (id) copyWithZone: (NSZone *)zone
{
#ifndef ETOILE_SERIALIZE
	id container = [super copyWithZone: zone];
	
	/* Copy objects which doesn't support encoding usually or must not be copied
	   but rather shared by the receiver and the copy. */
	[container setSource: [self source]];
	[container setDelegate: [self delegate]];
	
	return container;
#else
	
#endif
}

/** Deep copies are never created by the container itself, but they are instead
	delegated to the item group returned by -layoutItem. When the layout item
	receives a deep copy request it will call back -copy on each view (including
	containers) embedded in descendant items. Subview hierarchy will later get 
	transparently reconstructed when -updateLayout will be called on the 
	resulting layout item tree copy.
	
		View Tree							Layout Item Tree
	
	-> [container deepCopy] 
									-> [containerItem deepCopy] 
	-> [container copy]
									-> [childItem deepCopy]
	-> [subview copy] 
	
	For ETView and ETContainer, view copies created by -copy are shallow copies
	that don't include subviews unlike -copy invoked on NSView and other 
	related subclasses. Layout/Display view isn't copied either. However title 
	bar view is copied unlike other subviews (as explained in -[ETView copy]).
	Remember -[NSView copy] returns a deep copy (view hierachy copy) 
	but -[ETView copy] doesn't. */
- (id) deepCopy
{
	id item = [[self layoutItem] deepCopy];
	id container = [item supervisorView];
	
	// TODO: Finish to implement...
	// NSAssert3([container isKindOfClass: [ETContainer class]], 
	
	return container;
}

- (NSString *) description
{
	NSString *desc = [super description];
	
	desc = [@"<" stringByAppendingString: desc];
	desc = [desc stringByAppendingFormat: @" + %@>", [self layout], nil];
	return desc;
}

- (NSString *) displayName
{
	// FIXME: Trim the angle brackets out.
	return [self description];
}

/** Returns the layout item to which the receiver is bound to. 

This layout item can only be an ETLayoutItemGroup instance unlike ETView. See 
also -[ETView setLayoutItem:].

Never returns nil. */
- (id) layoutItem
{
	if ([[super layoutItem] isGroup] == NO)
		ETLog(@"WARNING: Layout item in a container must of ETLayoutItemGroup type");

	return [super layoutItem];
}

/* Private helper methods to sync display view and container */

/* Various adjustements necessary when layout object is a wrapper around an 
   AppKit view. This method is called on a regular basis each time a setting of
   the container is modified and needs to be mirrored on the display view. */
- (void) syncDisplayViewWithContainer
{
	NSInvocation *inv = nil;
	
	if (_layoutView != nil)
	{
		SEL doubleAction = @selector(forwardDoubleActionFromLayout:);
		id target = self;
		
		inv = RETAIN([self invocationForSelector: @selector(setDoubleAction:)]);
		[inv setArgument: &doubleAction atIndex: 2];
		[self sendInvocationToDisplayView: inv];
		
		inv = RETAIN([self invocationForSelector: @selector(setTarget:)]);
		[inv setArgument: &target atIndex: 2];
		[self sendInvocationToDisplayView: inv];
		
		BOOL hasVScroller = [self hasVerticalScroller];
		BOOL hasHScroller = [self hasHorizontalScroller];
		
		if ([self isScrollViewShown] == NO)
		{
			hasVScroller = NO;
			hasHScroller = NO;
		}
		
		inv = RETAIN([self invocationForSelector: @selector(setHasHorizontalScroller:)]);
		[inv setArgument: &hasHScroller atIndex: 2];
		[self sendInvocationToDisplayView: inv];
		
		inv = RETAIN([self invocationForSelector: @selector(setHasVerticalScroller:)]);
		[inv setArgument: &hasVScroller atIndex: 2];
		[self sendInvocationToDisplayView: inv];
		
		BOOL allowsEmptySelection = [self allowsEmptySelection];
		BOOL allowsMultipleSelection = [self allowsMultipleSelection];
		
		inv = RETAIN([self invocationForSelector: @selector(setAllowsEmptySelection:)]);
		[inv setArgument: &allowsEmptySelection atIndex: 2];
		[self sendInvocationToDisplayView: inv];
		
		inv = RETAIN([self invocationForSelector: @selector(setAllowsMultipleSelection:)]);
		[inv setArgument: &allowsMultipleSelection atIndex: 2];
		[self sendInvocationToDisplayView: inv];
	}
}

- (NSInvocation *) invocationForSelector: (SEL)selector
{
	NSInvocation *inv = [NSInvocation invocationWithMethodSignature: 
		[self methodSignatureForSelector: selector]];
	
	/* Method signature doesn't embed the selector, but only type infos related to it */
	[inv setSelector: selector];
	
	return inv;
}

- (void) sendInvocationToDisplayView: (NSInvocation *)inv
{
	//id result = [[inv methodSignature] methodReturnLength];
	
	if ([_layoutView respondsToSelector: [inv selector]])
	{
			[inv invokeWithTarget: _layoutView];
	}
	else if ([_layoutView isKindOfClass: [NSScrollView class]])
	{
		/* May be the display view is packaged inside a scroll view */
		id enclosedDisplayView = [(NSScrollView *)_layoutView documentView];
		
		if ([enclosedDisplayView respondsToSelector: [inv selector]]);
			[inv invokeWithTarget: enclosedDisplayView];
	}
	
	//if (inv != nil)
	//	[inv getReturnValue: &result];
		
	RELEASE(inv); /* Retained in -syncDisplayViewWithContainer otherwise it gets released too soon */
	
	//return result;
}

/** Returns the control view enclosed in the layout view if the latter is a
    scroll view, otherwise the returned view is identical to -layoutView. */
- (NSView *) layoutViewWithoutScrollView
{
	id layoutView = [self layoutView];

	if ([layoutView isKindOfClass: [NSScrollView class]])
		return [layoutView documentView];

	return layoutView;
}

- (void) forwardDoubleActionFromLayout: (id)sender
{
	id layout = [self layout];
	NSView *layoutView = [self layoutViewWithoutScrollView];
	NSEvent *evt = [NSApp currentEvent];

	NSAssert1(layoutView != nil, @"Layout must not be nil if a double action "
		@"is handed by the layout %@", sender);
	NSAssert2([sender isEqual: layoutView], @"sender %@ must be the layout "
		@"view %@ currently in uses", sender, layoutView);

	ETDebugLog(@"Double action on %@ in %@ with selected items %@", sender, evt,
		[layout selectedItems]);

	if ([layout respondsToSelector: @selector(doubleClickedItem)])
	{
		[self mouseDoubleClick: evt item: [layout doubleClickedItem]];
	}
	else
	{
		ETLog(@"WARNING: Layout %@ based on a layout view must implement "
			@"-doubleClickedItem", layout);
	}
}


/* Scrollers */

- (BOOL) letsLayoutControlsScrollerVisibility
{
	return NO;
}


- (void) setLetsLayoutControlsScrollerVisibility: (BOOL)layoutControl
{
	// FIXME: Implement or remove
}

/* About the container scroll view and layouts

   From API viewpoint, it makes little sense to keep these scroller methods if
   we offer a direct access to the underlying scroll view. However a layout view 
   may want to heavily alter the scroll view in a way that only works in this 
   specific layout case. That's why layouts have the choice to use or not the 
   scroll view set up and cached by the container.
   It also makes easier to support AppKit views/controls wrapped in a layout. 
   For example NSBrowser has a method like -setHasHorizontalScroller: but isn't 
   wrapped inside a scroll view. Setting up and tearing down the container 
   scroll view to be reused by a NSTableView-based layout or a NSTextView-based 
   layout would also introduce an extra chunk of non-trivial code.
   We only keep in sync (with the container scroll view) basic properties like 
   scroller visibility, when a layout uses its own scroll view. They are the 
   only scroll view settings which are very commonly altered independently of 
   the presentation (the layout in EtoileUI case). 
   NOTE: Another approach would be move this logic into ETScrollView but obvious 
   benefits have to be found. */

/** Returns YES when the vertical scroller of the current scroll view managed 
	by the container or its layout is visible, otherwise returns NO. */
- (BOOL) hasVerticalScroller
{
	return [[self scrollView] hasVerticalScroller];
}

/** Sets the vertical scroller visibility of the current scroll view that can 
	be owned either by the container or its layout.
	Even if both vertical and horizontal scroller are made invisible, this 
	method won't remove the scroll view managed by the container from the 
	decorator chain bound to its layout item. */
- (void) setHasVerticalScroller: (BOOL)scroll
{
	if (scroll)
	{
		[self setShowsScrollView: YES];
	}
	[[self scrollView] setHasVerticalScroller: scroll];
	
	/* Updated NSBrowser, NSOutlineView enclosing scroll view etc. */
	[self syncDisplayViewWithContainer];
}

/** Returns YES when the horizontal scroller of the current scroll view managed 
	by the container or its layout is visible, otherwise returns NO. */
- (BOOL) hasHorizontalScroller
{
	return [[self scrollView] hasHorizontalScroller];
}

/** Sets the horizontal scroller visibility of the current scroll view that can 
	be owned either by the container or its layout.
	Even if both vertical and horizontal scroller are made invisible, this 
	method won't remove the scroll view managed by the container from the 
	decorator chain bound to its layout item. */
- (void) setHasHorizontalScroller: (BOOL)scroll
{
	if (scroll)
	{
		[self setShowsScrollView: YES];
	}
	[[self scrollView] setHasHorizontalScroller: scroll];
	
	/* Updated NSBrowser, NSOutlineView enclosing scroll view etc. */
	[self syncDisplayViewWithContainer];
}

// TODO: Evaluates whether we really need to keep public the following methods 
// exposing NSScrollView directly. Would be cleaner to provide a ready to use 
// ETScrollView in the UI builder and the related inspector to configure it.

/** Returns the scroll view managed by the receiver to let you modify its 
	settings. 
	This underlying scroll view is wrapped inside an ETScrollView instance, 
	itself referenced by a layout item that can be inserted and removed in the 
	decorator chain by calling hide/unhide methods. */
- (NSScrollView *) scrollView
{
	id cachedDecorator = [self cachedScrollViewDecoratorItem];
	
	if (cachedDecorator == nil)
	{
		[self cacheScrollViewDecoratorItem: [self createScrollViewDecoratorItem]];
		cachedDecorator = [self cachedScrollViewDecoratorItem];
	}

	return (NSScrollView *)[[cachedDecorator supervisorView] mainView];
}

- (void) cacheScrollViewDecoratorItem: (ETLayoutItem *)decorator
{
	ASSIGN(_scrollViewDecorator, decorator);
}


- (ETLayoutItem *) cachedScrollViewDecoratorItem
{
	return _scrollViewDecorator;
}

/* When a new scroll view decorator is inserted in the decorator chain we cache 
   it. -unhidesScrollViewDecoratorItem triggers this call back. */
- (void) didChangeDecoratorOfItem: (ETLayoutItem *)item
{
	if ([item firstScrollViewDecoratorItem] != nil)
		[self cacheScrollViewDecoratorItem: [item firstScrollViewDecoratorItem]];
		
	// TODO: We might cache the position of the first scroll view decorator in  
	// the decorator chain in order to be able to reinsert it at the same 
	// position in -unhidesScrollViewDecoratorItem. We currently only support 
	// reinserting it in the first position.
}

/* Returns whether the scroll view of the current container is really used. If
   the container shows currently an AppKit control like NSTableView as display 
   view, the built-in scroll view of the table view is used instead of the one
   provided by the container. 
   It implies you can never have -hasScrollView returns NO and -isScrollViewShown 
   returns YES. There is no such exception with all other boolean combinations. */
- (BOOL) isScrollViewShown
{
	return _scrollViewShown;
}

- (BOOL) isContainerScrollViewInserted
{
	return ([[self layoutItem] firstScrollViewDecoratorItem] != nil);
}

/** Inserts a scroll view as the first decorator item bound to the receiver 
	layout item if no scroll view decorator can be found in the decorator chain. 
	If such a decorator already exists, does nothing.
	The receiver container caches a scroll view decorator, hence it is possible 
	to remove/insert the scroll view in the decorator chain by calling 
	hide/unhide methods without losing the scroll view settings.
	When no scroll view decorator has already been cached, behind the scene, 
	this method creates a ETScrollView instance and builds a decorator item with 
	this view. This new scroll view decorator item is finally inserted as the 
	first decorator. */
- (void) unhidesScrollViewDecoratorItem 
{
	if ([self isContainerScrollViewInserted])
		return;

	id scrollDecorator = [self cachedScrollViewDecoratorItem];	
	
	/* If no scroll view exists we create one even when a display view is in use
	   simply because we use the container scroll view instance to store all
	   scroller settings. We update any scroller settings defined in a display
	   view with that of the newly created scroll view.  */
	if (scrollDecorator == nil)
		scrollDecorator = [self createScrollViewDecoratorItem];

	// NOTE: Will call back -didChangeScrollDecoratorOfItem: which takes care of 
	// caching the scroll decorator
	[[self layoutItem] setDecoratorItem: scrollDecorator];
	//[_scrollView setAutoresizingMask: [self autoresizingMask]];
		
	// TODO: This should be handled rather on scroll view decorator 
	// insertion and probably in ETLayoutItem itself
	[[self layout] setContentSizeLayout: YES];
}

- (void) hidesScrollViewDecoratorItem 
{
	if ([self isContainerScrollViewInserted] == NO)
		return;
		
	NSAssert([[self scrollView] superview] != nil, @"A scroll view without "
		@"superview cannot be hidden");

	id scrollDecorator = [[self layoutItem] firstScrollViewDecoratorItem];
	id nextDecorator = [scrollDecorator decoratorItem];	
		
	[[scrollDecorator decoratedItem] setDecoratorItem: nextDecorator];
	//[self setAutoresizingMask: [_scrollView autoresizingMask]];
	
	// NOTE: The assertion below was added to ensure [self setFrame: 
	// [_scrollView frame]]; was correctly applied, it may be better to move
	// it in decorator handling of ETLayoutItem. As it is, it doesn't make 
	// much sense anymore because it is valid only when the scroll view is 
	// the first decorator of the layout item bound to the container.
	// WARNING: More about next line and following assertion can be read here: 
	// <http://www.cocoabuilder.com/archive/message/cocoa/2006/9/29/172021>
	// Stop also to receive any view/window notifications in ETContainer code 
	// before turning scroll view on or off.
	#if 0
	// This test will never work unless you retain scrollDecorator before 
	// removing it
	NSAssert1(NSEqualRects([self frame], [[scrollDecorator supervisorView] frame]), 
		@"Unable to update the frame of container %@, you must stop watch "
		@"any notifications posted by container before hiding or showing "
		@"its scroll view (Cocoa bug)", self);
	#endif

	// TODO: This should be handled rather on scroll view decorator 
	// removal and probably in ETLayoutItem itself
	[[self layout] setContentSizeLayout: NO];
}

- (void) setShowsScrollView: (BOOL)show
{
	if (_scrollViewShown == show)
		return;

	// FIXME: Asks layout whether it handles scroll view itself or not. If 
	// needed like with table layout, delegate scroll view handling.
	BOOL layoutHandlesScrollView = ([self layoutView] != nil);
	
	_scrollViewShown = show;

	if (layoutHandlesScrollView)
	{
		[self syncDisplayViewWithContainer];	
	}
	else
	{
		if (show)
		{
			[self unhidesScrollViewDecoratorItem];
		}
		else
		{
			[self hidesScrollViewDecoratorItem];
		}
	}
}

- (ETLayoutItem *) createScrollViewDecoratorItem
{
	ETScrollView *scrollViewWrapper = nil;
	
	scrollViewWrapper = [[ETScrollView alloc] initWithFrame: [self frame]];
	AUTORELEASE(scrollViewWrapper);

	NSScrollView *scrollView = (NSScrollView *)[scrollViewWrapper mainView];
	BOOL noVisibleScrollers = ([scrollView hasVerticalScroller] == NO &&
		[scrollView hasHorizontalScroller] == NO);
	NSAssert2(noVisibleScrollers, @"New scrollview %@ wrapper is expected have "
		"no visible scrollers to be used by %@", scrollViewWrapper, self);

	return [scrollViewWrapper layoutItem];
}

/** Returns the custom view that might have been provided by the layout set 
on -layoutItem.

Returns nil by default. Only returns a view when a view-based layout is used, 
see layout view related methods in ETLayout. */
- (NSView *) layoutView
{
	return _layoutView;
}

/** Sets the custom view provided by the layout set on -layoutItem. 

Never calls this method unless you write an ETLayout subclass.

Method called when we switch between layouts. Manipulating the layout view is 
the job of ETContainer, ETLayout instances may provide a layout view prototype
but they never never manipulate it as a subview in view hierachy. */
- (void) setLayoutView: (NSView *)view
{
	if (_layoutView == nil && view == nil)
		return;

	if (_layoutView == view && (_layoutView != nil || view != nil))
	{
		ETLog(@"WARNING: Trying to assign an identical display view to container %@", self);
		return;
	}
	
	[_layoutView removeFromSuperview];
	/* Retain indirectly by our layout item which retains the layout that 
	   provides this view. Also retain as a subview by us just below. */
	_layoutView = view; 

	if (view != nil) /* Set up layout view */
	{
		[self hidesScrollViewDecoratorItem];
		
		/* Inserts the layout view */
		[view removeFromSuperview];
		[view setFrameSize: [self frame].size];
		[view setFrameOrigin: NSZeroPoint];
		[self addSubview: view];
		
		[self syncDisplayViewWithContainer];
	}
	else /* Tear down layout view */
	{
		if ([self isScrollViewShown])
			[self unhidesScrollViewDecoratorItem];		
	}	
}

#if 0
- (void) setAutoresizingMask: (unsigned int)mask
{
	ETDebugLog(@"--- Resizing mask from %d to %d %@", [self autoresizingMask], mask, self);
	[super setAutoresizingMask: mask];
}
#endif

/* FIXME: Implement

- (ETLayoutOverflowStyle) overflowStyle
{

}

- (void) setOverflowStyle: (ETLayoutOverflowStyle)
{

}
*/

/* Selection */

- (BOOL) allowsMultipleSelection
{
	return _multipleSelectionAllowed;
}

- (void) setAllowsMultipleSelection: (BOOL)multiple
{
	_multipleSelectionAllowed = multiple;
	[self syncDisplayViewWithContainer];
}

- (BOOL) allowsEmptySelection
{
	return _emptySelectionAllowed;
}

- (void) setAllowsEmptySelection: (BOOL)empty
{
	_emptySelectionAllowed = empty;
	[self syncDisplayViewWithContainer];
}

/** point parameter must be expressed in receiver coordinates */
- (BOOL) doesSelectionContainsPoint: (NSPoint)point
{
	ETLayoutItem *item = [[self layout] itemAtLocation: point];

	if ([item isSelected])
	{
		NSAssert2([[self selectionIndexes] containsIndex: [self indexOfItem: item]],
			@"Mismatch between selection indexes and item %@ selected state in %@", 
			item, self);
		return YES;
	}
		
	return NO;

// NOTE: The code below could be significantly faster on large set of items
#if 0
	NSArray *selectedItems = [[self items] objectsAtIndexes: [self selectionIndexes]];
	NSEnumerator *e = [selectedItems objectEnumerator];
	ETLayoutItem *item = nil;
	BOOL hitSelection = NO;
	
	while ((item = [nextObject]) != nil)
	{
		if ([item displayView] != nil)
		{
			hitSelection = NSPointInRect(point, [[item displayView] frame]);
		}
		else /* Layout items uses no display view */
		{
			// FIXME: Implement
		}
	}
	
	return hitSelection;
#endif
}

/* Pick & Drop */

- (BOOL) shouldRemoveItemsAtPickTime
{
	return _removeItemsAtPickTime;
}

- (void) setShouldRemoveItemsAtPickTime: (BOOL)flag
{
	_removeItemsAtPickTime = flag;
}

- (void) setAllowsDragging: (BOOL)flag
{
	_dragAllowed = flag;
}

- (BOOL) allowsDragging
{
	return _dragAllowed;
}

- (void) setAllowsDropping: (BOOL)flag
{
	_dropAllowed = flag;
}

- (BOOL) allowsDropping
{
	// FIXME: We should rather check whether source implement dragging data
	// source methods.
	if ([self source] != nil)
		return NO;
	
	return _dropAllowed;
}

- (IBAction) copy: (id)sender
{
	[[[self layoutItem] eventHandler] copy: sender];
}

- (IBAction) paste: (id)sender
{
	[[[self layoutItem] eventHandler] paste: sender];
}

- (IBAction) cut: (id)sender
{
	[[[self layoutItem] eventHandler] cut: sender];
}

/* Grouping and Stacking */

- (void) group: (id)sender
{
	/*ETLayoutItem *item = [self itemAtIndex: [self selectionIndex]]; 
	
	if ([item isGroup])
	{
		[(ETLayoutItemGroup *)item make];
	}
	else
	{
		ETLog(@"WARNING: Layout item %@ must be an item group to be stacked", self);
	}
	
	if ([self canUpdateLayout])
		[self updateLayout];*/	
}

- (IBAction) stack: (id)sender
{
	ETLayoutItem *item = [self itemAtIndex: [self selectionIndex]]; 
	
	if ([item isGroup])
	{
		[(ETLayoutItemGroup *)item stack];
	}
	else
	{
		ETLog(@"WARNING: Layout item %@ must be an item group to be stacked", self);
	}
	
	if ([self canUpdateLayout])
		[self updateLayout];	
}

/* Item scaling */

- (float) itemScaleFactor
{
	return _itemScale;
}

- (void) setItemScaleFactor: (float)factor
{
	_itemScale = factor;
	if ([self canUpdateLayout])
		[self updateLayout];
}

/* Rendering Chain */

- (void) render
{
	//[_layoutItems makeObjectsPerformSelector: @selector(render)];
}

- (void) render: (NSMutableDictionary *)inputValues
{
	[[self items] makeObjectsPerformSelector: @selector(render:) withObject: nil];
}

- (void) drawRect: (NSRect)rect
{
	/* Takes care of drawing layout items with a view */
	[super drawRect: rect];
	
	/* Now we must draw layout items without view... using either a cell or 
	   their own renderer. Layout item are smart enough to avoid drawing their
	   view when they have one. */
	//[[self items] makeObjectsPerformSelector: @selector(render:) withObject: nil];
}

/* Actions */

/** Returns usually the lowest subcontainer of the receiver which contains 
    location point in the view hierarchy. For any other kind of subviews, hit 
	test doesn't succeed by default to eliminate potential issues you may 
	encounter by using subclasses of NSControl like NSImageView as layout item 
	view.
	If you want to layout controls which should support direct interaction like
	checkbox or popup menu, you can turn hit test on by calling 
	-setEnablesHitTest: with YES.
	If the point is located in the receiver itself but outside of any 
	subcontainers, returns self. When no subcontainer can be found, returns 
	nil. 
	*/
- (NSView *) hitTest: (NSPoint)location
{
	NSView *subview = [super hitTest: location];
	
	/* If -[NSView hitTest:] returns a container or if we use an AppKit control 
	   as a display view, we simply return the subview provided by 
	   -[NSView hitTest:]
	   If hit test is turned on, everything should be handled as usual. */
	if ([self layoutView] || [self isHitTestEnabled] 
	 || [subview isKindOfClass: [self class]])
	{
		return subview;
	}
	else if (NSPointInRect(location, [self frame]))
	{
		return self;
	}
	else
	{
		return nil;
	}
}

- (void) setEnablesHitTest: (BOOL)passHitTest
{ 
	_subviewHitTest = passHitTest; 
}

- (BOOL) isHitTestEnabled { return _subviewHitTest; }

- (void) setTarget: (id)target
{
	_target = target;
	
	/* If a display view is used, sync its settings with container */
	[self syncDisplayViewWithContainer];
}

- (id) target
{
	return _target;
}

- (void) setDoubleAction: (SEL)selector
{
	_doubleClickAction = selector;
	
	/* If a display view is used, sync its settings with container */
	[self syncDisplayViewWithContainer];
}

- (SEL) doubleAction
{
	return _doubleClickAction;
}

- (ETLayoutItem *) doubleClickedItem
{
	return _doubleClickedItem;
}

/* Overriden NSView methods */

/* GNUstep doesn't rely on -setFrameSize: in -setFrame: unlike Cocoa, so we 
   patch frame parameter in -setFrame: too.
   See -setFrame: below to understand the reason behind this method. */
#ifdef GNUSTEP
- (void) setFrame: (NSRect)frame
{
	NSRect patchedFrame = frame;
	
	ETDebugLog(@"-setFrame to %@", NSStringFromRect(frame));
		
	if ([self isContainerScrollViewInserted])
	{
		NSSize clipViewSize = [[self scrollView] contentSize];

		if (clipViewSize.width < frame.size.width || clipViewSize.height < frame.size.height)
		{
			patchedFrame.size = clipViewSize;
		}
	}
	
	[super setFrame: patchedFrame];
	
	if ([self canUpdateLayout])
		[self updateLayout];
}
#endif

/* We override this method to patch the size in case we are located in a scroll 
   view owned by the receiver container. We must patch the container size to be 
   sure it will never be smaller than the clip view size. If both container and 
   clip view size don't match, you cannot click on the background to unselect 
   items and the drawing of the container background doesn't fully fill the 
   visible area of the scroll view.
   -setFrame: calls -setFrameSize: on Cocoa but not on GNUstep. */
- (void) setFrameSize: (NSSize)size
{
	NSSize patchedSize = size;

	//ETDebugLog(@"-setFrameSize: to %@", NSStringFromSize(size));

	// NOTE: Very weird resizing behavior can be observed if the following code 
	/// is executed when a layout view is in use. The layout view size will be 
	// constrained to the clip view size of the cached scroll view decorator.
	if ([self isContainerScrollViewInserted])
	{
		NSSize clipViewSize = [[self scrollView] contentSize];

		if (size.width < clipViewSize.width)
			patchedSize.width = clipViewSize.width;
		if (size.height < clipViewSize.height)
			patchedSize.height = clipViewSize.height;
	}
	
	[super setFrameSize: patchedSize];
	
	if ([self canUpdateLayout])
		[self updateLayout];
}

@end


/* Deprecated (DO NOT USE, WILL BE REMOVED LATER) */

@implementation ETContainer (Deprecated)

- (id) delegate
{
	return [[self layoutItem] delegate];
}

- (void) setDelegate: (id)delegate
{
	[[self layoutItem] setDelegate: delegate];
}

- (id) source
{
	return [[self layoutItem] source];
}

- (void) setSource: (id)source
{
	[[self layoutItem] setSource: source];
}

- (NSString *) representedPath
{
	return [[self layoutItem] representedPathBase];
}

- (void) setRepresentedPath: (NSString *)path
{
	[[self layoutItem] setRepresentedPathBase: path];
}

/* Inspecting (WARNING CODE TO BE REPLACED BY THE NEW EVENT HANDLING) */

- (IBAction) inspect: (id)sender
{
	[[self layoutItem] inspect: sender];
}

- (IBAction) inspectSelection: (id)sender
{
	ETDebugLog(@"Inspect %@ selection", self);

	id inspector = [[self layoutItem] inspector];

	if (inspector == nil)
		inspector = [[ETInspector alloc] init]; // NOTE: Leak
	[inspector setInspectedObjects: [(id)[self layoutItem] selectedItemsInLayout]];
	[[inspector panel] makeKeyAndOrderFront: self];
}

/* Layout */

/** See -[ETLayoutItemGroup isAutolayout] */
- (BOOL) isAutolayout
{
	return [(ETLayoutItemGroup *)[self layoutItem] isAutolayout];
}

/** See -[ETLayoutItemGroup setAutolayout:] */
- (void) setAutolayout: (BOOL)flag
{
	[(ETLayoutItemGroup *)[self layoutItem] setAutolayout: flag];
}

/** See -[ETLayoutItemGroup canUpdateLayout] */
- (BOOL) canUpdateLayout
{
	return [(ETLayoutItemGroup *)[self layoutItem] canUpdateLayout];
}

/** See -[ETLayoutItemGroup updateLayout] */
- (void) updateLayout
{
	[[self layoutItem] updateLayout];
}

/** See -[ETLayoutItemGroup reloadAndUpdateLayout] */
- (void) reloadAndUpdateLayout
{
	[(ETLayoutItemGroup *)[self layoutItem] reloadAndUpdateLayout];
}

/** See -[ETLayoutItemGroup layout] */
- (ETLayout *) layout
{
	return [(ETLayoutItemGroup *)[self layoutItem] layout];
}

/** See -[ETLayoutItemGroup setLayout] */
- (void) setLayout: (ETLayout *)layout
{
	[(ETLayoutItemGroup *)[self layoutItem] setLayout: layout];
}

/*  Manipulating Layout Item Tree */

/** See -[ETLayoutItemGroup addItem:] */
- (void) addItem: (ETLayoutItem *)item
{
	[(ETLayoutItemGroup *)[self layoutItem] addItem: item];
}

/** See -[ETLayoutItemGroup insertItem:atIndex:] */
- (void) insertItem: (ETLayoutItem *)item atIndex: (int)index
{
	[(ETLayoutItemGroup *)[self layoutItem] insertItem: item atIndex: index];
}

/** See -[ETLayoutItemGroup removeItem:] */
- (void) removeItem: (ETLayoutItem *)item
{
	[(ETLayoutItemGroup *)[self layoutItem] removeItem: item];
}

/** See -[ETLayoutItemGroup removeItem:atIndex:] */
- (void) removeItemAtIndex: (int)index
{
	[(ETLayoutItemGroup *)[self layoutItem] removeItemAtIndex: index];
}

/** See -[ETLayoutItemGroup itemAtIndex:] */
- (ETLayoutItem *) itemAtIndex: (int)index
{
	return [(ETLayoutItemGroup *)[self layoutItem] itemAtIndex: index];
}

/** See -[ETLayoutItemGroup addItems:] */
- (void) addItems: (NSArray *)items
{
	[(ETLayoutItemGroup *)[self layoutItem] addItems: items];
}

/** See -[ETLayoutItemGroup removeItems] */
- (void) removeItems: (NSArray *)items
{
	[(ETLayoutItemGroup *)[self layoutItem] removeItems: items];
}

/** See -[ETLayoutItemGroup removeAllItems] */
- (void) removeAllItems
{
	[(ETLayoutItemGroup *)[self layoutItem] removeAllItems];
}

/** See -[ETLayoutItemGroup indexOfItem:] */
- (int) indexOfItem: (ETLayoutItem *)item
{
	return [(ETLayoutItemGroup *)[self layoutItem] indexOfItem: item];
}

/** See -[ETLayoutItemGroup containsItem:] */
- (BOOL) containsItem: (ETLayoutItem *)item
{
	return [(ETLayoutItemGroup *)[self layoutItem] containsItem: item];
}

/** See -[ETLayoutItemGroup numberOfItems] */
- (int) numberOfItems
{
	return [(ETLayoutItemGroup *)[self layoutItem] numberOfItems];
}

/** See -[ETLayoutItemGroup items] */
- (NSArray *) items
{
	return [(ETLayoutItemGroup *)[self layoutItem] items];
}

/** See -[ETLayoutItemGroup selectedItemsInLayout] */
- (NSArray *) selectedItemsInLayout
{
	return [(ETLayoutItemGroup *)[self layoutItem] selectedItemsInLayout];
}

/** See -[ETLayoutItemGroup selectionIndexPaths] */
- (NSArray *) selectionIndexPaths
{
	return [(ETLayoutItemGroup *)[self layoutItem] selectionIndexPaths];
}

/** See -[ETLayoutItemGroup setSelectionIndexPaths] */
- (void) setSelectionIndexPaths: (NSArray *)indexPaths
{
	[(ETLayoutItemGroup *)[self layoutItem] setSelectionIndexPaths: indexPaths];
}

- (void) setSelectionIndexes: (NSIndexSet *)indexes
{
	return [(ETLayoutItemGroup *)[self layoutItem] setSelectionIndexes: indexes];
}

- (NSMutableIndexSet *) selectionIndexes
{
	return [(ETLayoutItemGroup *)[self layoutItem] selectionIndexes];
}

- (void) setSelectionIndex: (unsigned int)index
{
	return [(ETLayoutItemGroup *)[self layoutItem] setSelectionIndex: index];
}

- (unsigned int) selectionIndex
{
	return [(ETLayoutItemGroup *)[self layoutItem] selectionIndex];
}

@end


/* Selection Caching Code (not used currently) */

#if 0
- (void) setSelectionIndexes: (NSIndexSet *)indexes
{
	int numberOfItems = [[self items] count];
	int lastSelectionIndex = [indexes lastIndex];
	
	ETDebugLog(@"Set selection indexes to %@ in %@", indexes, self);
	
	if (lastSelectionIndex > (numberOfItems - 1) && lastSelectionIndex != NSNotFound) /* NSNotFound is a big value and not -1 */
	{
		ETLog(@"WARNING: Try to set selection index %d when container %@ only contains %d items",
			lastSelectionIndex, self, numberOfItems);
		return;
	}
	
	/* Discard previous selection */
	if ([_selection count] > 0)
	{
		NSArray *selectedItems = [[self items] objectsAtIndexes: _selection];
		NSEnumerator *e = [selectedItems objectEnumerator];
		ETLayoutItem *item = nil;
		
		while ((item = [e nextObject]) != nil)
		{
			[item setSelected: NO];
		}
		[_selection removeAllIndexes];
	}

	/* Update selection */
	if (lastSelectionIndex != NSNotFound)
	{
		/* Cache selection locally in this container */
		if ([indexes isKindOfClass: [NSMutableIndexSet class]])
		{
			ASSIGN(_selection, indexes);
		}
		else
		{
			ASSIGN(_selection, [indexes mutableCopy]);
		}
	
		/* Update selection state in layout items directly */
		NSArray *selectedItems = [[self items] objectsAtIndexes: _selection];
		NSEnumerator *e = [selectedItems objectEnumerator];
		ETLayoutItem *item = nil;
			
		while ((item = [e nextObject]) != nil)
		{
			[item setSelected: YES];
		}
	}
	
	/* Finally propagate changes by posting notification */
	NSNotification *notif = [NSNotification 
		notificationWithName: ETContainerSelectionDidChangeNotification object: self];
	
	if ([[self delegate] respondsToSelector: @selector(containerSelectionDidChange:)])
		[[self delegate] containerSelectionDidChange: notif];

	[[NSNotificationCenter defaultCenter] postNotification: notif];
	
	/* Reflect selection change immediately */
	[self display];
}

- (NSMutableIndexSet *) selectionIndexes
{
	return AUTORELEASE([_selection mutableCopy]);
}

- (void) setSelectionIndex: (int)index
{
	int numberOfItems = [[self items] count];
	
	ETDebugLog(@"Modify selected item from %d to %d of %@", [self selectionIndex], index, self);
	
	/* Check new selection validity */
	NSAssert1(index >= 0, @"-setSelectionIndex: parameter must not be a negative value like %d", index);
	if (index > (numberOfItems - 1) && index != NSNotFound) /* NSNotFound is a big value and not -1 */
	{
		ETLog(@"WARNING: Try to set selection index %d when container %@ only contains %d items",
			index, self, numberOfItems);
		return;
	}

	/* Discard previous selection */
	if ([_selection count] > 0)
	{
		NSArray *selectedItems = [[self items] objectsAtIndexes: _selection];
		NSEnumerator *e = [selectedItems objectEnumerator];
		ETLayoutItem *item = nil;
		
		while ((item = [e nextObject]) != nil)
		{
			[item setSelected: NO];
		}
		[_selection removeAllIndexes];
	}
	
	/* Update selection */
	if (index != NSNotFound)
	{
		[_selection addIndex: index]; // cache
		[[self itemAtIndex: index] setSelected: YES];
	}
	
	NSAssert([_selection count] == 0 || [_selection count] == 1, @"-setSelectionIndex: must result in either no index or a single index but not more");
	
	/* Finally propagate changes by posting notification */
	NSNotification *notif = [NSNotification 
		notificationWithName: ETContainerSelectionDidChangeNotification object: self];
	
	if ([[self delegate] respondsToSelector: @selector(containerSelectionDidChange:)])
		[[self delegate] containerSelectionDidChange: notif];

	[[NSNotificationCenter defaultCenter] postNotification: notif];
	
	/* Reflect selection change immediately */
	[self display];
}

- (int) selectionIndex
{
	return [_selection firstIndex];
}
#endif