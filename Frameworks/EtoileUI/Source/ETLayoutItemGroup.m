/*  <title>ETLayoutItemGroup</title>

	ETLayoutItemGroup.m
	
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
#import <EtoileFoundation/NSObject+Model.h>
#import <EtoileFoundation/Macros.h>
#import "ETLayoutItemGroup.h"
#import "ETLayoutItemGroup+Mutation.h"
#import "ETLayoutItem+Factory.h"
#import "ETFlowLayout.h"
#import "ETLineLayout.h"
#import "ETContainer.h"
#import "ETContainer+Controller.h"
#import "NSView+Etoile.h"
#import "ETCompatibility.h"

#define DEFAULT_FRAME NSMakeRect(0, 0, 50, 50)

/* Properties */
NSString *kSourceProperty = @"source";
NSString *kDelegateProperty = @"delegate";

/* Notifications */
NSString *ETItemGroupSelectionDidChangeNotification = @"ETItemGroupSelectionDidChangeNotification";

@interface ETLayoutItem (SubclassVisibility)
- (void) setDisplayView: (ETView *)view;
@end

@interface ETContainer (PackageVisibility)
- (int) checkSourceProtocolConformance;
- (void) syncDisplayViewWithContainer;
@end

@interface ETLayoutItemGroup (Private)
- (id) initWithItems: (NSArray *)layoutItems view: (NSView *)view value: (id)value representedObject: (id)repObject;
- (BOOL) hasNewLayout;
- (void) setHasNewLayout: (BOOL)flag;
- (void) collectSelectionIndexPaths: (NSMutableArray *)indexPaths
					 relativeToItem: (ETLayoutItemGroup *)pathBaseItem;
- (void) applySelectionIndexPaths: (NSMutableArray *)indexPaths
                   relativeToItem: (ETLayoutItemGroup *)pathBaseItem;
- (void) display: (NSMutableDictionary *)inputValues item: (ETLayoutItem *)item dirtyRect: (NSRect)dirtyRect inView: (NSView *)view;

/* Deprecated (DO NOT USE, WILL BE REMOVED LATER) */
- (id) initWithLayoutItems: (NSArray *)layoutItems view: (NSView *)view value: (id)value;
- (id) initWithLayoutItems: (NSArray *)layoutItems view: (NSView *)view;
@end


@implementation ETLayoutItemGroup

/* Ugly hack to shut down the compiler so it doesn't pretend we don't fully
   implement ETLayoutingContext protocol. */
- (void) setNeedsDisplay: (BOOL)now { [super setNeedsDisplay: now]; }

/* Initialization */

/** <init /> Designated initializer */
- (id) initWithItems: (NSArray *)layoutItems view: (NSView *)view value: (id)value representedObject: (id)repObject
{
    self = [super initWithView: view value: value representedObject: repObject];

    if (self != nil)
    {
		_layoutItems = [[NSMutableArray alloc] init];
		if (layoutItems != nil)
		{
			[self addItems: layoutItems];
		}
		_layout = nil;
		[self setStackedItemLayout: [ETFlowLayout layout]];
		[self setUnstackedItemLayout:[ETLineLayout layout]];
		_isStack = NO;
		_autolayout = YES;
		_usesLayoutBasedFrame = NO;
		[self setHasNewLayout: NO];
		[self setHasNewContent: NO];
		[self setShouldMutateRepresentedObject: YES];
    }

    return self;
}

/* Overriden ETLayoutItem designated initializer */
- (id) initWithView: (NSView *)view value: (id)value representedObject: (id)repObject
{
	return [self initWithItems: nil view: view value: value representedObject: repObject];
}

- (id) initWithItems: (NSArray *)layoutItems view: (NSView *)view
{
	return [self initWithItems: layoutItems view: view value: nil representedObject: nil];
}

- (id) init
{
	return [self initWithItems: nil view: nil];
}

- (void) dealloc
{
	DESTROY(_layout);
	DESTROY(_stackedLayout);
	DESTROY(_unstackedLayout);
	DESTROY(_layoutItems);

	[super dealloc];
}

/** Returns a copy of the receiver. See also -[ETLayoutItem copyWithZone:].

All layouts from the receiver returned by -layout, -stackedItemLayout, 
-unstackedItemLayout are also copied since a layout cannot be shared between 
several item groups.

The returned copy is mutable because ETLayoutItemGroup cannot be immutable. */ 
- (id) copyWithZone: (NSZone *)zone
{
	ETLayoutItemGroup *item = (ETLayoutItemGroup *)[(id)super copyWithZone: zone];
	
	item->_layoutItems = [[NSMutableArray alloc] init];
	
	// TODO: Layout objects must be copied because they support only one layout 
	// context. If you share a layout like that: 
	// [item setLayout: [self layout]];
	// -[ETLayoutItemGroup setLayout:] will set the item copy as the layout 
	// context replacing the current value of -[[self layout] layoutContext].
	// This latter value is precisely self.
	/*[item setLayout: [[self layout] layoutPrototype]];
	[item setStackedItemLayout: [[self stackedItemLayout] layoutPrototype]];
	[item setUnstackedItemLayout: [[self unstackedItemLayout] layoutPrototype]];*/
	item->_isStack = [self isStack];
	item->_autolayout = [self isAutolayout];
	item->_usesLayoutBasedFrame = [self usesLayoutBasedFrame];
	item->_shouldMutateRepresentedObject = [self shouldMutateRepresentedObject];

	return item;
}

- (id) deepCopy
{
	ETLayoutItemGroup *item = [super deepCopy];
	NSArray *copiedChildItems = [[self items] valueForKey: @"deepCopy"];

	[item addItems: copiedChildItems];
	// TODO: Test if using -autorelease instead of -release results in a quicker 
	// deep copy (when plenty of items are involved).
	[copiedChildItems makeObjectsPerformSelector: @selector(release)];

	return item;
}

/* Property Value Coding */

- (NSArray *) properties
{
	NSArray *properties = A(@"layout", kSourceProperty, kDelegateProperty);

	return [[super properties] arrayByAddingObjectsFromArray: properties];
}

/* Finding Container */

/** Returns YES. An ETLayoutItemGroup is always a group and a collection by 
default. */
- (BOOL) isGroup
{
	return YES;
}

- (BOOL) isContainer
{
	return [[self view] isKindOfClass: [ETContainer class]];
}

/* Traversing Layout Item Tree */

/** Returns a normal path relative to the receiver, by translating indexPath
into a layout item sequence and concatenating the names of all layout items in
the sequence. Each index in the index path references a child item by its index
in the parent item. 

Resulting path uses '/' as path separator and always begins by '/'. If an item 
has no name (-name returns nil or an empty string), its index is used instead of 
the name as a path component.<br />
For index path 3.4.8.0, a valid translation would be:
	      3     .4 .8   .0
	/BlackCircle/4/Tulip/Zone

Returns '/' if indexPath is nil or empty. */
- (NSString *) pathForIndexPath: (NSIndexPath *)indexPath
{
	NSString *path = @"/";
	ETLayoutItem *item = self;
	NSString *name = nil;
	unsigned int index = NSNotFound;

	for (unsigned int i = 0; i < [indexPath length]; i++)
	{
		index = [indexPath indexAtPosition: i];
		
		if (index == NSNotFound)
			return nil;

		NSAssert2([item isGroup], @"Item %@ "
			@"must be layout item group to resolve the index path %@", 
			item, indexPath);
		NSAssert3(index < [(ETLayoutItemGroup *)item numberOfItems], @"Index "
			@"%d in path %@ position %d must be inferior to children item "
			@"number", index + 1, indexPath, i);

		item = [(ETLayoutItemGroup *)item itemAtIndex: index];
		name = [item name];
		if (name != nil && [name isEqualToString: @""] == NO)
		{
			path = [path stringByAppendingPathComponent: name];
		}
		else
		{
			path = [path stringByAppendingPathComponent: 
				[NSString stringWithFormat: @"%d", index]];	
		}
	}

	return path;
}

/** Returns an index path relative to the receiver, by translating normal path
into a layout item sequence and pushing parent relative index of each layout
item in the sequence into an index path. Each index in the index path references
a child item by its index in the parent item. 

Resulting path uses internally '.' as path separator and internally always
begins by an index number and not a path separator.

For the translation, empty path component or component made of path separator 
'/' are skipped in path parameter.<br />
For index path /BlackCircle/4/Tulip/Zone, a valid translation would be:
	/BlackCircle/4/Tulip/Zone
	      3     .4 .8   .0

Take note 3.5.8.0 could be a valid translation too, because a name could be a
number which is unrelated to the item index used by its parent item to reference 
it. */
- (NSIndexPath *) indexPathForPath: (NSString *)path
{
	NSIndexPath *indexPath = [NSIndexPath indexPath];
	NSArray *pathComponents = [path pathComponents];
	NSString *pathComp = nil;
	ETLayoutItem *item = self;
	int index = -1;

	for (int position = 0; position < [pathComponents count]; position++)
	{
		pathComp = [pathComponents objectAtIndex: position];

		if ([pathComp isEqualToString: @"/"] || [pathComp isEqualToString: @""])
			continue;

		if ([item isGroup] == NO)
		{
			/* path is invalid */
			indexPath = nil;
			break;
		}
		item = [(ETLayoutItemGroup *)item itemAtPath: pathComp];

		/* If no item can be found by interpreting pathComp as an identifier, 
		   try to interpret pathComp as a number */
		if (item == nil)
		{
			index = [pathComp intValue];
			/* -intValue returns 0 when no numeric value is present to be 
			   converted */
			if (index == 0 && [pathComp isEqualToString: @"0"] == NO)
			{
				/* path is invalid */
				indexPath = nil;
				break;
			}

			/* Verify the index truly references a child item */
			if (index >= [(ETLayoutItemGroup *)item numberOfItems])
			{
				/* path is invalid */
				indexPath = nil;
				break;
			}
			item = [(ETLayoutItemGroup *)item itemAtIndex: index];
		}
		else
		{
			index = [[item parentItem] indexOfItem: item];
		}

		/*NSAssert1(index == 0 && [pathComp isEqual: @"0"] == NO,
			@"Path components must be indexes for path %@", path);
		NSAssert2([item isGroup], @"Item %@ "
			@"must be layout item group to resolve the index path %@", 
			item, indexPath);
		NSAssert3(index < [[(ETLayoutItemGroup *)item items] count], @"Index "
			@"%d in path %@ position %d must be inferior to children item "
			@"number", index + 1, position, path);*/

		indexPath = [indexPath indexPathByAddingIndex: index];
	}

	return indexPath;
}

/** Returns the layout item child identified by the index path paremeter 
interpreted as relative to the receiver. */
- (ETLayoutItem *) itemAtIndexPath: (NSIndexPath *)path
{
	int length = [path length];
	ETLayoutItem *item = self;

	for (unsigned int i = 0; i < length; i++)
	{
		if ([item isGroup])
		{		
			item = [(ETLayoutItemGroup *)item itemAtIndex: [path indexAtPosition: i]];
		}
		else
		{
			item = nil;
			break;
		}
	}

	return item;
}

/** Returns the layout item child identified by the path paremeter interpreted 
as relative to the receiver. 

Whether the path begins by '/' or not doesn't modify the result. */
- (ETLayoutItem *) itemAtPath: (NSString *)path
{
	NSArray *pathComponents = [path pathComponents];
	ETLayoutItem *item = self;
	
	FOREACH(pathComponents, pathComp, NSString *)
	{
		if (pathComp == nil || [pathComp isEqualToString: @"/"] || [pathComp isEqualToString: @""])
			continue;
	
		if ([item isGroup])
		{
			NSArray *childItems = [(ETLayoutItemGroup *)item items];
			item = [childItems firstObjectMatchingValue: pathComp 
			                                     forKey: @"name"];
		}
		else
		{
			item = nil;
			break;
		}
	}

	return item;
}

/** Sets the represented path base associated with the receiver. When a valid 
represented base is set, the receiver becomes a base item. See also -isBaseItem, 
-baseItem, -representedPath and -representedPathBase in ETLayoutItem.

The represented path base should be a navigational path into the model whose 
content is currently presented by the receiver. In that way, it is useful to 
keep track of your location inside the model currently browsed. Tree-related 
methods implemented by a data source are passed paths which are subpaths of this 
path base.

A path base is only critical when a source is used, otherwise it's up to the 
developer to track the level of navigation inside the tree structure. 

You should use paths like '/', '/blabla/myModelObjectName'. You cannot pass an 
empty string to this method or it will throw an invalid argument exception. If 
you want no represented path base, use nil. 

Without a source, you can use -setRepresentedPathBase: as a conveniency to 
remember the represented object location within the model graph that is 
presented by the receiver. */
- (void) setRepresentedPathBase: (NSString *)aPath
{
	if ([aPath isEqual: @""])
	{
		[NSException raise: NSInvalidArgumentException format: @"For %@ "
			@"-setRepresentedPathBase: argument must never be an empty string", self];
		
	}

	SET_PROPERTY(aPath, kRepresentedPathBaseProperty);
}

/* Manipulating Layout Item Tree */

/** Handles the view visibility of child items with a role similar to 
-setVisibleItems: that is called by layouts. 

This method is called when you insert an item in an item group with a layout 
which doesn't require an update in that case, otherwise the view insertion is 
managed by requesting a layout update which ultimately calls back 
-setVisibleItems:. 

NOTE: Having a null layout class may be a solution to get rid of 
-handleAttachViewOfItem: and -handleDetachViewOfItem:. */
- (void) handleAttachViewOfItem: (ETLayoutItem *)item
{
	/* Typically needed if your item has no view and gets added to an item 
	   group without a layout. Without this check -addSuview: [item displayView]
	   results in a crash. */
	if ([item displayView] == nil) /* No view to attach */
		return;

	[[item displayView] removeFromSuperview];
	/* Only insert the item view if the layout is a fixed/free layout and the 
	   receiver has a view itself. 
	   TODO: Probably make more explicit the nil layout check and improve in a
	   way or another the handling of the nil view case. */
	if ([self layout] == nil && [self view] != nil)
		[[self view] addSubview: [item displayView]];
}

/** Symetric method to -handleAttachViewOfItem: */
- (void) handleDetachViewOfItem: (ETLayoutItem *)item
{
	if ([item displayView] == nil) /* No view to detach */
		return;

	[[item displayView] removeFromSuperview];
}

/** <override-dummy />Handles any necessary adjustments to be done right before
item is made a child item of the receiver. This method is available to be
overriden in subclasses that want to extend or modify the item insertion
behavior.

The default implementation takes to care to remove item from any existing parent 
item, then updates the parent item reference to be the receiver.<br />
You must always call the superclass implementation.

Symetric method to -handleDetachItem: */
- (void) handleAttachItem: (ETLayoutItem *)item
{
	RETAIN(item);
	if ([item parentItem] != nil)
	{
		[[item parentItem] removeItem: item];
	}
	[item setParentItem: self];
	RELEASE(item);
	[self handleAttachViewOfItem: item];
}

/** <override-dummy />Handles any necessary adjustments to be done right before
item is removed as a child item from the receiver. This method is available to
be overriden in subclasses that want to extend or modify the item removal
behavior.

The default implementation only updates the parent item reference to be nil. <br />
You must always call the superclass implementation.

Symetric method to -handleAttachItem: */
- (void) handleDetachItem: (ETLayoutItem *)item
{
	[item setParentItem: nil];
	[self handleDetachViewOfItem: item];
}

/** See -[ETLayoutItemGroup setRepresentedObject:].

If necessary, marks the receiver as having new content to be layouted, otherwise
the layout is told the layout item tree hasn't been mutated. Although this only
holds when the layout item tree is built directly from the represented object by
the mean of ETCollection protocol. */
- (void) setRepresentedObject: (id)model
{
	[super setRepresentedObject: model];
	if ([self usesRepresentedObjectAsProvider])
		[self setHasNewContent: YES];
}

/** Returns YES when the item tree mutation are propagated to the represented
object, otherwise returns NO if it's up to you to reflect structural changes of
the layout item tree onto the model object graph. By default, this method
returns YES.

Mutations are triggered by calling children or collection related methods
like -addItem:, -insertItem:atIndex:, removeItem:, addObject: etc. 

<strong>The returned value is meaningful only if the receiver is a base item.
In this case, the value applies to all related descendant items (by being
looked up by descendant items).</strong> */
- (BOOL) shouldMutateRepresentedObject
{
	return _shouldMutateRepresentedObject;
}

/** Sets whether the layout item tree mutation are propagated to the represented
object or not. 

<strong>The value set is meaningful only if the receiver is a base item, 
otherwise the value is simply ignored.</strong>  */
- (void) setShouldMutateRepresentedObject: (BOOL)flag
{
	_shouldMutateRepresentedObject = flag;
}

/** Returns YES when the child items are automatically generated by wrapping the
elements of the represented object collection into ETLayoutItem or
ETLayoutItemGroup instances.

To use represented objects as providers in the layout item tree connected to 
the receiver, you have to set the source of the receiver to be the receiver 
itself. The code would be something like <example>
[itemGroupsetSource: itemGroup]</example>. */
- (BOOL) usesRepresentedObjectAsProvider
{
	return ([[[self baseItem] source] isEqual: [self baseItem]]);
}

/** Returns the source which provides the content presented by the receiver.

A source implements either ETIndexSource or ETPathSource protocols. If the
receiver handles the layout item tree directly without the help of a source
object, then this method returns nil. */
- (id) source
{
	return GET_PROPERTY(kSourceProperty);
}

/** Sets the source which provides the content displayed by the receiver. A
source can be any objects conforming to ETIndexSource or ETPathSource protocol.

So you can write you own data source object by implementing either:
<enum>
<item><list>
<item>-numberOfItemsInItemGroup:</item>
<item>-itemGroup:itemAtIndex:</item>
</list></item>
<item><list>
<item>-itemGroup:numberOfItemsAtPath:</item>
<item>-itemGroup:itemAtPath:</item>
</list></item>
</enum>

Another common solution is to use the receiver itself as a source, in that 
case -usesRepresentedObjectAsProvider returns YES. And the receiver will 
generate the layout item tree bound to it by retrieving any child objects of the 
represented object (through ETCollection protocol) and wrapping them into 
ETLayoutItem or ETLayoutItemGroup objects based on whether these childs 
implements ETCollection or not.

You can also combine these abilities with an off-the-shelf controller object like
ETController. See -setController to do so. This brings extra flexibility such as:
<list>
<item>template item and item group for the generated layout items</item>
<item>easy to use add, insert and remove actions with template model object and 
model group for the represented objects to insert wrapped in layout items</item>
<item>sorting</item>
<item>searching</item>
</list>

Finally when -source returns nil, it's always possible to build and manage a 
layout item tree structure in a static fashion by yourself.

Take note that modifying a source is followed by a layout update, the new
content is immediately loaded and displayed. By setting a source, the receiver
represented path base is automatically set to '/' unless another path was set
previously. If you pass nil to get rid of a source, the represented path base 
isn't reset to nil but keeps its actual value in order to maintain it as a base
item and avoid unpredictable changes to the event handling logic. */
- (void) setSource: (id)source
{
	/* By safety, avoids to trigger extra updates */
	if ([GET_PROPERTY(kSourceProperty) isEqual: source])
		return;

	[self removeAllItems]; 	/* Resets any particular state like selection */
	SET_PROPERTY(source, kSourceProperty);

	/* Make base item if needed */
	if (source != nil && [self isBaseItem] == NO)
		[self setRepresentedPathBase: @"/"];
}

/** Returns the delegate associated with the receiver. 

See also -setDelegate:. */
- (id) delegate
{
	return GET_PROPERTY(kDelegateProperty);
}

/** Sets the delegate associated with the receiver. 

A delegate is only useful if the receiver is a base item, otherwise it will  
be ignored. */
- (void) setDelegate: (id)delegate
{
	SET_PROPERTY(delegate, kDelegateProperty);
}

/*	Alternatively, if you have a relatively small and static tree structure,
	you can also build the tree by yourself and assigns the root item to the
	container by calling -addItem:. In this case, the user will have the 
	possibility to */
- (void) addItem: (ETLayoutItem *)item
{
	//ETDebugLog(@"Add item in %@", self);
	[self handleAdd: nil item: item];
}

- (void) insertItem: (ETLayoutItem *)item atIndex: (int)index
{
	//ETDebuLog(@"Insert item in %@", self);
	[self handleInsert: nil item: item atIndex: index];
}

- (void) removeItem: (ETLayoutItem *)item
{
	//ETDebugLog(@"Remove item in %@", self);
	[self handleRemove: nil item: item];
}

- (void) removeItemAtIndex: (int)index
{
	ETLayoutItem *item = [_layoutItems objectAtIndex: index];
	[self removeItem: item];
}

- (ETLayoutItem *) itemAtIndex: (int)index
{
	return [_layoutItems objectAtIndex: index];
}

/** Returns the first item in the children of the receiver, with a result 
    identical to [self itemAtIndex: 0].
    Similar to -firstObject method for collections (see ETCollection).*/
- (ETLayoutItem *) firstItem
{
	return [_layoutItems firstObject];
}

/** Returns the last item in the children of the receiver, with a result 
    identical to [self itemAtIndex: [self numberOfItems] - 1].
    Similar to -lastObject method for collections (see ETCollection).*/
- (ETLayoutItem *) lastItem
{
	return [_layoutItems lastObject];
}

- (void) addItems: (NSArray *)items
{
	//ETDebugLog(@"Add items in %@", self);
	[self handleAdd: nil items: items];
}

- (void) removeItems: (NSArray *)items
{
	//ETDebugLog(@"Remove items in %@", self);
	[self handleRemove: nil items: items];
}

- (void) removeAllItems
{
	ETDebugLog(@"Remove all items in %@", self);
	// FIXME: Temporary solution which is quite slow
	[self handleRemove: nil items: [self items]];

#if 0	
	// NOTE: If a selection cache is implemented, the cache must be cleared
	// here because this method doesn't the primitive mutation method 
	// -removeItem:
	
	[_layoutItems makeObjectsPerformSelector: @selector(setParentLayoutItem:) withObject: nil];
	[_layoutItems removeAllObjects];
	if ([self canUpdateLayout])
		[self updateLayout];
#endif
}

// FIXME: (id) parameter rather than (ETLayoutItem *) turns off compiler 
// conflicts with menu item protocol which also implements this method. 
// Fix compiler.
- (int) indexOfItem: (id)item
{
	return [_layoutItems indexOfObject: item];
}

- (BOOL) containsItem: (ETLayoutItem *)item
{
	return ([self indexOfItem: (id)item] != NSNotFound);
}

- (int) numberOfItems
{
	return [_layoutItems count];
}

- (NSArray *) items
{
	return [NSArray arrayWithArray: _layoutItems];
}

/** Returns all children items under the control of the receiver. 

An item is said to be under the control of an item group, when you can traverse
the branch leading to the item without crossing a parent item declared as a base 
item. An item group becomes a base item when a represented path base is set, in
other words when -representedPathBase doesn't return nil. See also -isBaseItem.

This method collects every items the layout item subtree (excluding the
receiver) by doing a preorder traversal, the resulting collection is a flat list
of every items in the tree.

If you are interested by collecting descendant items in another traversal order, 
you have to implement your own version of this method. */
- (NSArray *) itemsIncludingRelatedDescendants
{
	// TODO: This code is probably quite slow by being written in a recursive 
	// style and allocating/resizing many arrays instead of using a single 
	// linked list. Test whether optimization are needed or not really...
	NSMutableArray *collectedItems = [NSMutableArray array];

	FOREACHI([self items], item)
	{
		[collectedItems addObject: item];

		if ([item isGroup] && [item hasValidRepresentedPathBase] == NO)
			[collectedItems addObjectsFromArray: [item itemsIncludingRelatedDescendants]];
	}

	return collectedItems;
}

/** Returns all descendant items of the receiver, including immediate children.

This method collects every items the layout item subtree (excluding the
receiver) by doing a preorder traversal, the resulting collection is a flat list
of every items in the tree. 

If you are interested in collecting descendant items in another traversal order,
you have to implement your own version of this method. */
- (NSArray *) itemsIncludingAllDescendants
{
	// TODO: This code is probably quite slow by being written in a recursive 
	// style and allocating/resizing many arrays instead of using a single 
	// linked list. Test whether optimization are needed or not really ...
	NSMutableArray *collectedItems = [NSMutableArray array];

	FOREACHI([self items], item)
	{
		[collectedItems addObject: item];

		if ([item isGroup])
			[collectedItems addObjectsFromArray: [item itemsIncludingAllDescendants]];
	}

	return collectedItems;
}

/** Returns whether the receiver can be reloaded presently with -reload. */
- (BOOL) canReload
{
	BOOL hasSource = ([[self baseItem] source] != nil);

	return hasSource && ![self isReloading];
}

/** Tries to reload the content of the receiver, but only if it can be reloaded. 

This method can be safely called even if the receiver has no source or doesn't 
inherit a source from a base item. */
- (void) reloadIfNeeded
{
	if ([self canReload])
		[self reload];
}

/** Reloads the content by removing all existing childrens and requesting all
the receiver immediate children to the source. */
- (void) reload
{
	_reloading = YES;

	BOOL hasSource = ([[self baseItem] source] != nil);

	/* Retrieve layout items provided by source */
	if (hasSource)
	{
		NSArray *itemsFromSource = [self itemsFromSource];
		[self removeAllItems];
		[self addItems: itemsFromSource];
	}
	else
	{
		ETLog(@"WARNING: Impossible to reload %@ because the layout item miss " 
			@"a source %@", self, [[self baseItem] source]);
	}
	
	_reloading = NO;
}

/* Layout */

- (BOOL) hasNewLayout { return _hasNewLayout; }

- (void) setHasNewLayout: (BOOL)flag { _hasNewLayout = flag; }

- (ETLayout *) layout
{
	return _layout;
}

- (void) setLayout: (ETLayout *)layout
{
	if (_layout == layout)
		return;

	//ETDebugLog(@"Modify layout from %@ to %@ in %@", _layout, layout, self);
	
	BOOL wasAutolayoutEnabled = [self isAutolayout];
	
	/* Disable autolayout to avoid spurious updates triggered by stuff like
	   view/container frame modification on layout view insertion */
	[self setAutolayout: NO];
	
	[_layout setLayoutContext: nil]; /* Ensures -[ETLayout tearDown] is called */
	ASSIGN(_layout, layout);
	[self setHasNewLayout: YES];
	[layout setLayoutContext: self];

	// FIXME: We should move code to set display view when necessary here. By
	// calling -setDisplayView: [_container layoutView] we wouldn't
	// need anymore to call -syncDisplayViewWithContainer here.
	// All display view set up code is currently in -renderWithLayoutItems:
	// of AppKit-based layouts. Part of this code should be put inside 
	// overidden -layoutView method in each ETLayout suclasses.
	if ([self isContainer])
		[(ETContainer *)[self supervisorView] syncDisplayViewWithContainer];
	
	[self setAutolayout: wasAutolayoutEnabled];
	if ([self canUpdateLayout])
		[self updateLayout];
}

/** Returns the first ancestor layout item, including itself, whose layout 
   returns YES to -isOpaque (see ETLayout). If none is found, returns self. */
- (ETLayoutItemGroup *) ancestorItemForOpaqueLayout
{
	ETLayoutItemGroup *parent = self;

	while (parent != nil)
	{
		if ([[parent layout] isOpaque])
			return parent;
		
		parent = [parent parentItem];
	}

	return self; /* Found no ancestor with an opaque layout */
}

/** Attemps to reload the children items from the source and updates the layout 
    by asking the first ancestor item with an opaque layout to do so. */
- (void) reloadAndUpdateLayout
{
	[self reload];
	[[self ancestorItemForOpaqueLayout] updateLayout];
}

// TODO: This code is a little bit messy, refactor...
- (void) updateLayout
{
	if ([self layout] == nil)
		return;
	
	BOOL isNewLayoutContent = ([self hasNewContent] || [self hasNewLayout]);
	
	/* Update layout of descendant items before all because our own layout 
	   depends on the layout of the descendant items. Layout update may modify
	   number and frame of descendant items, thereby producing different layout
	   conditions higher in the hierarchy (like ourself). */
	if ([[self items] count] > 0)
		[[self items] makeObjectsPerformSelector: @selector(updateLayout)];
	
	/* Delegate layout rendering to custom layout object */
	[[self layout] render: nil isNewContent: isNewLayoutContent];
	
	[[self closestAncestorContainer] setNeedsDisplay: YES];
	
	/* Unset needs layout flags */
	[self setHasNewContent: NO];
	[self setHasNewLayout: NO];
	
	// FIXME: Redisplay closestAncestorContainer with our rect
	/*ETContainer *closestContainer = [self closestAncestorContainer];
	NSRect closestViewInsideRect = [closestContainer frame];
	NSRect dirtyRect = [self frame];
	
	closestViewInsideRect.origin = NSZeroPoint;
	if ([self displayView] != nil)
	{
		dirtyRect = [[self displayView] convertRect: dirtyRect toView: closestContainer];
	}
	dirtyRect = NSIntersectionRect(dirtyRect, closestViewInsideRect);
	[closestContainer setNeedsDisplayInRect: dirtyRect];*/
}

- (BOOL) canUpdateLayout
{
	return [self isAutolayout] && ![self isReloading] && ![[self layout] isRendering];
}

/** Returns YES if mutating the receiver content by calling -addItem:, 
    -insertItem:atIndex:, -removeItem: etc. triggers a layout update and a 
	redisplay, otherwise returns NO when you must call -updateLayout by yourself 
	after mutating the receiver content. 
	By default, returns YES, hence there is usually no need to call 
	-updateLayout and marks the receiver or a parent item for redisplay. */
- (BOOL) isAutolayout
{
	return _autolayout;
}

/** Sets whether mutating the receiver content by calling -addItem:, 
    -insertItem:atIndex:, -removeItem: etc. triggers a layout update and a 
	redisplay.
	If you need to add, remove or insert a large set of child items, in order 
	to only recompute the layout once and also avoid a lot of extra redisplay, 
	you should disable the autolayout, and restore it later after mutating 
	the receiver children in meantime. Take note that enabling the autolayout 
	doesn't trigger a layout update, so -updateLayout must be called when 
	autolayout is disabled or was just restored. */
- (void) setAutolayout: (BOOL)flag
{
	_autolayout = flag;
}

/** Returns YES if the item frame may vary with the layout of the child items 
    that makes up the content, otherwise returns NO if the frame is static and 
	will always remain identical after updating the layout. By default, returns 
	NO.
	This method is used by the drawing code of the layout item tree to know 
	if the whole receiver content must be redrawn subsequently to a layout 
	change. */
- (BOOL) usesLayoutBasedFrame
{
	return _usesLayoutBasedFrame;
}

/** Sets to YES to indicate that the item frame may vary with the layout of the 
    child items that makes up the content, otherwise sets to NO if the frame is 
	static and will always remain identical after updating the layout.
	You rarely need to invoke this method unless you write a layout that alter 
	the frame of its layout context. */
- (void) setUsesLayoutBasedFrame: (BOOL)flag
{
	_usesLayoutBasedFrame = flag;
}

/* Rendering */

- (void) debugDrawingInRect: (NSRect)rect
{
	// NOTE: For debugging, don't remove.
	if ([self respondsToSelector: @selector(layout)] && [[self layout] isKindOfClass: [ETFlowLayout class]])
	{
		[[NSColor orangeColor] set];
		//NSRectClip([self frame]);
		NSRectFill(rect);
	}
}

/** See -[ETLayoutItem render:dirtyRect:inView:]. The most important addition of 
    this method is to manage the drawing of children items by calling this method 
	recursively on them. */
- (void) render: (NSMutableDictionary *)inputValues dirtyRect: (NSRect)dirtyRect inView: (NSView *)view 
{
	//ETLog(@"Render %@ dirtyRect %@ in %@", self, NSStringFromRect(dirtyRect), view);
	
	//ETView *drawingView = [self supervisorView];
	NSView *renderView = view;	
	BOOL hasLockedFocus = NO;
	
	// TODO: Enable later to allow drawing a layout item tree in any views.
	//if (renderView == nil)
	//	renderView = [self drawingView];
	
	// NOTE: Probably not useful, -render: can lock the focus by safety and 
	// in other cases this is the reponsability of the framework user.
	// Somewhat as in -[NSCell drawWithFrame:inView:]
	//if ([[NSView focusView] isEqual: renderView] == NO)
	//{
	//	[renderView lockFocus];
	//	hasLockedFocus = YES;
	//}

	// TODO: Move in -render:. Keeping this code here prevents us to draw in 
	// any views passed as view parameter.
	//if (drawingView != nil)
	//{
	//	NSAssert2(renderView == drawingView, @"Supervisor view %@ and render view %@ must match",
	//		renderView, drawingView);
	//}
	
	NSRect drawingFrame = [self drawingFrame];

	if ([self usesLayoutBasedFrame] || NSIntersectsRect(dirtyRect, drawingFrame))
	{
		BOOL usesLayoutView = ([[self layout] layoutView] != nil);

		#ifdef DEBUG_DRAWING
		[self debugDrawingInRect: dirtyRect];
		#endif

	   /* We intersect our dirtyRect with our drawing frame, so we don't get 
	      a dirtyRect that includes views of existing decorator items in case our 
		  decorator chain isn't empty. */
		NSRect realDirtyRect = NSIntersectionRect(dirtyRect, [self drawingFrame]);
		[super render: inputValues dirtyRect: realDirtyRect inView: view];
		
		/* Render the layout-specific tree if needed */
		
		id layout = [self layout];
		if ([layout respondsToSelector: @selector(rootItem)])
		{
			[self display: inputValues item: [layout rootItem] dirtyRect: dirtyRect inView: view];
		}

		/* Render child items (if the layout doesn't handle it) */
		
		if (usesLayoutView)
			return;
			
		NSEnumerator *e = [[self items] reverseObjectEnumerator];
		ETLayoutItem *item = nil;

		while ((item = [e nextObject]) != nil)
		{
			/* We intersect our dirtyRect with the drawing frame of the item to be 
		       drawn, so the child items don't receive the drawing frame of their 
		       parent, but their own. Also restricts the dirtyRect so it doesn't 
		       encompass any decorators set on the item. */
			NSRect childDirtyRect = [item convertRectFromParent: realDirtyRect];
			childDirtyRect = NSIntersectionRect(childDirtyRect, [item drawingFrame]);
			
			/* In case, dirtyRect is only a redraw rect on the parent and not on 
			   the entire parent frame, we try to optimize by not redrawing the 
			   items that lies outside of the dirtyRect. */
			if (NSEqualRects(childDirtyRect, NSZeroRect))
				continue;

			[self display: inputValues item: item dirtyRect: childDirtyRect inView: renderView];
		}
	}
	
	if (hasLockedFocus)
		[view unlockFocus];
}

/** Displays item by adjusting the graphic context for the drawing, then calling 
    -render:dirtyRect:inView: on it, and finally restoring the graphic context. 
	You should never need to call this method directly. */
- (void) display: (NSMutableDictionary *)inputValues item: (ETLayoutItem *)item 
	dirtyRect: (NSRect)newDirtyRect inView: (NSView *)renderView
{
	 /* When the item has a view, it waits to be asked to draw directly by its 
	    view before rendering anything. 
		To explain it in a more detailed but complex way... If a parent item 
		indirectly requests to draw the item by asking us to redraw, we decline 
		and wait the control return to the view who initiated the drawing and 
		this view asks the item view to draw itself as a subview.
		Hence we only draw child items with no display view (no supervisor view
		as a byproduct).
		
		FIXME: Verifying the item has no supervisor view isn't enough, because it 
		may be enclosed in a view owned by a decorator. In such case, this view 
		will be asked to draw by the view hierarchy and overwrite the item 
		drawing since it occurs below it (in a superview). 
		
		See also INTERLEAVED_DRAWING in ETView. */
	BOOL shouldDrawItem = ([item displayView] == nil);
			
	if (shouldDrawItem == NO)
		return;

#ifdef DEBUG_DRAWING		
	NSRect itemRect = [item convertRectFromParent: [item frame]];
	[[NSColor yellowColor] set];
	[NSBezierPath setDefaultLineWidth: 4.0];
	[NSBezierPath strokeRect: itemRect];
#endif
				
	NSAffineTransform *transform = [NSAffineTransform transform];
	
	/* Modify coordinate matrix when the layout item doesn't use a view for 
	   drawing. */
	if ([item supervisorView] == nil)
	{
		/* Translate */
		[transform translateXBy: [item x] yBy: [item y]];
	}
	/* Flip if needed */
	if ([self isFlipped] != [item isFlipped]) /* != [NSGraphicContext/renderView isFlipped] */
	{
		[transform translateXBy:0.0 yBy: [item height]];
		[transform scaleXBy:1.0 yBy:-1.0];
	}
	[transform concat];
	
	[item render: inputValues dirtyRect: newDirtyRect inView: renderView];
				
	/* Reset the coordinates matrix */
	[transform invert];
	[transform concat];
}

/** Returns the visible child items of the receiver.

This is a shortcut method for -visibleItemsForItems:. */
- (NSArray *) visibleItems
{
	return [self visibleItemsForItems: [self items]];
}

/** Sets the visible child items of the receiver, by taking care of inserting
and removing the item display views based on the visibility of the layout items.

This is a shortcut method for -visibleItemsForItems:. */
- (void) setVisibleItems: (NSArray *)visibleItems
{
	return [self setVisibleItems: visibleItems forItems: [self items]];
}
/** Returns the visible child items of the receiver.

You shouldn't need to call this method by yourself, unless you write an
ETCompositeLayout subclass which usually requires the receiver displays layout
items, that don't belong to it, as children. */
- (NSArray *) visibleItemsForItems: (NSArray *)items
{
	NSMutableArray *visibleItems = [NSMutableArray array];

	FOREACH(items, item, ETLayoutItem *)
	{
		if ([item isVisible])
			[visibleItems addObject: item];
	}

	return visibleItems;
}

/** Sets the visible child items of the receiver, by taking care of inserting
and removing the item display views based on the visibility of the layout items.

This method is typically called by the layout of the receiver once the layout 
rendering is finished, in order to adjust the visibility of views and update the 
visible property of the child items. You shouldn't need to call this method by 
yourself (see -visibleItemsForItems:). */
- (void) setVisibleItems: (NSArray *)visibleItems forItems: (NSArray *)items
{
// FIXME: Make a bottom top traversal to find the first view which can be used 
// as superview for the visible layout item views. Actually this isn't needed
// or supported because all ETLayoutItemGroup instances must embed a container.
// This last point is going to become purely optional.
	ETContainer *container = nil;

	if ([self isContainer])
		container = (ETContainer *)[self view];

	FOREACH(items, item, ETLayoutItem *)
	{
		if ([visibleItems containsObject: item])
		{
			[item setVisible: YES];
			if (container != nil && [[container subviews] containsObject: [item displayView]] == NO
			     && [item displayView] != nil )
			{
				[container addSubview: [item displayView]];
				ETDebugLog(@"Inserted view at %@", NSStringFromRect([[item displayView] frame]));
			}
		}
		else
		{
			[item setVisible: NO];
			if (container != nil && [[container subviews] containsObject: [item displayView]])
			{
				[[item displayView] removeFromSuperview];
				ETDebugLog(@"Removed view at %@", NSStringFromRect([[item displayView] frame]));
			}
		}
	}
}

/* Grouping */

- (ETLayoutItemGroup *) makeGroupWithItems: (NSArray *)items
{
	ETLayoutItemGroup *itemGroup = nil;
	ETLayoutItemGroup *prevParent = nil;
	int firstItemIndex = NSNotFound;
	
	if (items != nil && [items count] > 0)
	{
		NSEnumerator *e = [[self items] objectEnumerator];
		ETLayoutItem *item = [e nextObject];
		
		prevParent = [item parentLayoutItem];
		firstItemIndex = [prevParent indexOfItem: item];
		
		/* Try to find a common parent shared by all items */
		while ((item = [e nextObject]) != nil)
		{
			if ([[item parentLayoutItem] isEqual: prevParent] == NO)
			{
				prevParent = nil;
				break;
			}
		}
	}
		
	/* Will reparent each layout item to itemGroup */
	itemGroup = [ETLayoutItemGroup layoutItemGroupWithLayoutItems: items];
	/* When a parent shared by all items exists, inserts new item group where
	   its first item was previously located */
	if (prevParent != nil)
		[prevParent insertItem: itemGroup atIndex: firstItemIndex];
	
	return itemGroup;
}

/** Dismantles the receiver layout item group. If all items owned by the item */
- (NSArray *) unmakeGroup
{
	NSArray *items = [self items];
	int itemGroupIndex = [_parentItem indexOfItem: self];
	
	RETAIN(self);
	[_parentItem removeItem: self];
	/* Delay release the receiver until we fully step out of receiver's 
	   instance methods (like this method). */
	AUTORELEASE(self);

	// TODO: Use a reverse object enumerator or eventually implement -insertItems:atIndex:
	FOREACH([self items], item, ETLayoutItem *)
	{
		[_parentItem insertItem: item atIndex: itemGroupIndex];		
	}
	
	return items;
}

/* Stacking */

+ (NSSize) stackSize
{
	return NSMakeSize(200, 200);
}

- (ETLayout *) stackedItemLayout
{
	return _stackedLayout;
}

- (void) setStackedItemLayout: (ETLayout *)layout
{
	ASSIGN(_stackedLayout, layout);
}

- (ETLayout *) unstackedItemLayout
{
	return _unstackedLayout;
}

- (void) setUnstackedItemLayout: (ETLayout *)layout
{
	ASSIGN(_unstackedLayout, layout);
}

- (void) setIsStack: (BOOL)flag
{
	if (_isStack == NO)
	{
		if ([[self view] isKindOfClass: [ETContainer class]] == NO)
		{
			/*NSRect stackFrame = ETMakeRect(NSZeroPoint, [ETLayoutItemGroup stackSize]);
			ETContainer *container = [[ETContainer alloc] 
				initWithFrame: stackFrame layoutItem: self];*/
			// FIXME: Insert the container on the fly
		}
		[[self container] setItemScaleFactor: 0.7];
		[self setSize: [ETLayoutItemGroup stackSize]];
	}
		
	_isStack = flag;
}

- (BOOL) isStack
{
	return _isStack;
}

- (BOOL) isStacked
{
	return [self isStack] && [[self layout] isEqual: [self stackedItemLayout]];
}

- (void) stack
{
	/* Turn item group into stack if necessary */
	[self setIsStack: YES];
	[self reloadIfNeeded];
	[self setLayout: [self stackedItemLayout]];
}

- (void) unstack
{
	/* Turn item group into stack if necessary */
	[self setIsStack: YES];
	[self reloadIfNeeded];
	[self setLayout: [self unstackedItemLayout]];
}

/* Selection */

/** Returns the index of the first selected item which is an immediate child of 
the receiver. If there is none, returns NSNotFound. 

Calling this method is equivalent to [[self selectionIndexes] firstIndex].

Take note that -selectionIndexPaths may return one or multiple values when this
method returns NSNotFound. See -selectionIndexes also. */
- (unsigned int) selectionIndex
{
	return [[self selectionIndexes] firstIndex];
}

/** Sets the selected item identified by index in the receiver and discards any 
existing selection index paths previously set.

Posts an ETItemGroupSelectionDidChangeNotification. */
- (void) setSelectionIndex: (unsigned int)index
{
	ETDebugLog(@"Modify selection index from %d to %d of %@", [self selectionIndex], index, self);

	/* Check new selection validity */
	NSAssert1(index >= 0, @"-setSelectionIndex: parameter must not be a negative value like %d", index);

	NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
	
	if (index != NSNotFound)
		[indexes addIndex: index];

	[self setSelectionIndexes: indexes];
}

/** Returns all indexes matching selected items which are immediate children of 
the receiver.

Put in another way, the method returns the first index of all index paths with a 
length equal one. */
- (NSMutableIndexSet *) selectionIndexes
{
	NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];

	FOREACH([self selectionIndexPaths], indexPath, NSIndexPath *)
	{
		if ([indexPath length] == 1)
			[indexes addIndex: [indexPath firstIndex]];
	}

	return indexes;
}

/** Sets the selected items identified by indexes in the receiver and discards 
any existing selection index paths previously set.

Posts an ETItemGroupSelectionDidChangeNotification. */
- (void) setSelectionIndexes: (NSIndexSet *)indexes
{
	int numberOfItems = [[self items] count];
	int lastSelectionIndex = [[self selectionIndexes] lastIndex];

	ETDebugLog(@"Set selection indexes to %@ in %@", indexes, self);

	if (lastSelectionIndex > (numberOfItems - 1) && lastSelectionIndex != NSNotFound) /* NSNotFound is a big value and not -1 */
	{
		ETLog(@"WARNING: Try to set selection index %d when %@ only contains %d items",
			  lastSelectionIndex, self, numberOfItems);
		return;
	}

	/* Update selection */
	[self setSelectionIndexPaths: [indexes indexPaths]];
}

- (void) collectSelectionIndexPaths: (NSMutableArray *)indexPaths
                     relativeToItem: (ETLayoutItemGroup *)pathBaseItem
{
	FOREACHI([self items], item)
	{
		if ([item isSelected])
			[indexPaths addObject: [item indexPathFromItem: pathBaseItem]];

		if ([item isGroup])
			[item collectSelectionIndexPaths: indexPaths relativeToItem: pathBaseItem];
	}
}


/** Returns the index paths of selected items in layout item subtree of the the 
receiver. */
- (NSArray *) selectionIndexPaths
{
	NSMutableArray *indexPaths = [NSMutableArray array];

	[self collectSelectionIndexPaths: indexPaths relativeToItem: self];

	return indexPaths;
}

/** Selects every descendant items which match the index paths passed in 
parameter and deselects all other descendant items of the receiver.

TODO: This is crude because we deselect everything without taking care of base 
items we encounter during the recursive traversal of the subtree... See
-[ETLayout setSelectionIndexPaths:] to understand the issue more thoroughly.
Moreover the method is surely extremly slow if called many times within a short
time interval on a subtree that consists of thousand items or more. */
- (void) applySelectionIndexPaths: (NSMutableArray *)indexPaths 
                   relativeToItem: (ETLayoutItemGroup *)pathBaseItem
{
	FOREACHI([self items], item)
	{
		NSIndexPath *itemIndexPath = [item indexPathFromItem: pathBaseItem];
		if ([indexPaths containsObject: itemIndexPath])
		{
			[item setSelected: YES];
			[indexPaths removeObject: itemIndexPath];
		}
		else
		{
			[item setSelected: NO];
		}
		if ([item isGroup])
			[item applySelectionIndexPaths: indexPaths relativeToItem: pathBaseItem];
	}
}

/** Sets the selected items in the layout item subtree attached to the receiver. 

Posts an ETItemGroupSelectionDidChangeNotification. */
- (void) setSelectionIndexPaths: (NSArray *)indexPaths
{
	[self applySelectionIndexPaths: [NSMutableArray arrayWithArray: indexPaths] 
	                relativeToItem: self];

	/* Finally propagate changes by posting notification */
	NSNotification *notif = [NSNotification 
		notificationWithName: ETItemGroupSelectionDidChangeNotification object: self];
	
	if ([[self delegate] respondsToSelector: @selector(itemGroupSelectionDidChange:)])
		[[self delegate] itemGroupSelectionDidChange: notif];
	
	[[NSNotificationCenter defaultCenter] postNotification: notif];

	/* For opaque layouts that may need to keep in sync the selection state of 
	   their custom UI. */
	[[self layout] selectionDidChangeInLayoutContext];

	/* Reflect selection change immediately */
	[[self supervisorView] display]; // TODO: supervisorView is probably not the best choice...
}

/** Returns the selected child items belonging to the receiver. 

The returned collection only includes immediate children, other selected 
descendant items below these childrens in the layout item subtree are excluded. */
- (NSArray *) selectedItems
{
	return [[self items] objectsMatchingValue: [NSNumber numberWithBool: YES] 
	                                   forKey: @"isSelected"];
}

/** Returns selected descendant items reported by the active layout through 
-[ETLayout selectedItems].

You should call this method to obtain the selection in most cases and not
-selectedItems. */
- (NSArray *) selectedItemsInLayout
{
	NSArray *layoutSelectedItems = [[self layout] selectedItems];

	if (layoutSelectedItems != nil)
	{
		return layoutSelectedItems;
	}
	else
	{
		return [self selectedItems];
	}
}

/** You should rarely need to invoke this method. */
- (NSArray *) selectedItemsIncludingRelatedDescendants
{
	NSArray *descendantItems = [self itemsIncludingRelatedDescendants];

	return [descendantItems objectsMatchingValue: [NSNumber numberWithBool: YES] 
	                                      forKey: @"isSelected"];
}

/** You should rarely need to invoke this method. */
- (NSArray *) selectedItemsIncludingAllDescendants
{
	NSArray *descendantItems = [self itemsIncludingAllDescendants];

	return [descendantItems objectsMatchingValue: [NSNumber numberWithBool: YES] 
	                                      forKey: @"isSelected"];
}

/* Collection Protocol */

- (BOOL) isOrdered
{
	return YES;
}

- (BOOL) isEmpty
{
	return ([self numberOfItems] == 0);
}

- (unsigned int) count
{
	return [self numberOfItems];
}

- (id) content
{
	return [self items];
}

- (NSArray *) contentArray
{
	return [self items];
}

/** Adds object to the child items of the receiver, eventually autoboxing the 
	object if needed.
	If the object is a layout item, it is added directly to the layout items as
	it would be by calling -addItem:. If the object isn't an instance of some
	ETLayoutItem subclass, it gets autoboxed into a layout item that is then 
	added to the child items. 
	Autoboxing means the object is set as the represented object (or value) of 
	the item to be added. If the object replies YES to -isGroup, an 
	ETLayoutItemGroup instance is created instead of instantiating a simple 
	ETLayoutItem. 
	Also if the receiver or the base item bound to it has a container, the 
	instantiated item could also be either a deep copy of -templateItem or 
	-templateItemGroup when such template are available (not nil). -templateItem
	is retrieved when object returns NO to -isGroup, otherwise 
	-templateItemGroup is retrieved (-isGroup returns YES). */
- (void) addObject: (id)object
{
	id item = [object isLayoutItem] ? object : [self itemWithObject: object isValue: [object isCommonObjectValue]];
	
	if ([object isLayoutItem] == NO)
		ETDebugLog(@"Boxed object %@ in item %@ to be added to %@", object, item, self);

	[self addItem: item];
}

- (void) insertObject: (id)object atIndex: (unsigned int)index
{
	id item = [object isLayoutItem] ? object : [self itemWithObject: object isValue: [object isCommonObjectValue]];
	
	if ([object isLayoutItem] == NO)
		ETDebugLog(@"Boxed object %@ in item %@ to be inserted in %@", object, item, self);

	[self insertItem: item atIndex: index];
}

/** Removes object from the child items of the receiver, eventually trying to 
	remove items with represented objects matching the object. */
- (void) removeObject: (id)object
{
	/* Try to remove object by matching it against child items */
	if ([object isLayoutItem] && [self containsItem: object])
	{
		[self removeItem: object];
	}
	else
	{
		/* Remove items with boxed object matching the object to remove */	
		NSArray *itemsMatchedByRepObject = nil;
		
		itemsMatchedByRepObject = [[self items] 
			objectsMatchingValue: object forKey: @"representedObject"];
		[self removeItems: itemsMatchedByRepObject];
		
		itemsMatchedByRepObject = [[self items] 
			objectsMatchingValue: object forKey: @"value"];
		[self removeItems: itemsMatchedByRepObject];
	}
}

/* ETLayoutingContext */

- (float) itemScaleFactor
{
	if ([[self view] respondsToSelector: @selector(itemScaleFactor)])
	{
		return	[(id)[self view] itemScaleFactor];
	}
	else
	{
		ETLog(@"WARNING: Layout item %@ doesn't respond to -itemScaleFactor", self);
		return 0;
	}
}

/* ETLayoutingContext scroll view related methods */

/* -documentVisibleRect size */
- (NSSize) visibleContentSize
{
	if ([[self view] respondsToSelector: @selector(contentSize)])
	{
		return	[(id)[self view] contentSize];
	}
	else if ([[self view] respondsToSelector: @selector(scrollView)]
	 && [[(id)[self view] scrollView] respondsToSelector: @selector(contentSize)])
	{
		return [[(id)[self view] scrollView] contentSize];
	}
	else
	{
		ETLog(@"WARNING: Layout item %@ doesn't respond to -contentSize", self);
		return NSZeroSize;
	}
}

- (BOOL) isScrollViewShown
{
	if ([[self view] respondsToSelector: @selector(isScrollViewShown)])
	{
		return	[(id)[self view] isScrollViewShown];
	}
	else
	{
		ETLog(@"WARNING: Layout item %@ doesn't respond to -isScrollViewShown", self);
		return NO;
	}
}

		/* The frame may be patched by the display view, that's why 
		   _frame = rect would be incorrect. When the display view is embedded
		   inside a scroll view, the display view is the document view of the
		   scroll view and must fit perfectly into it.
		   For more details, see -[ETContainer setFrameSize:] */
- (void) setContentSize: (NSSize)size
{
	if ([[self view] respondsToSelector: @selector(setContentSize:)])
	{
		[(id)[self view] setContentSize: size];
	}
	else if ([[self view] respondsToSelector: @selector(scrollView)]
	 && [[(id)[self view] scrollView] isKindOfClass: [NSScrollView class]])
	{
		[[[(id)[self view] scrollView] documentView] setFrameSize: size];		
	}
	else
	{
		ETLog(@"WARNING: Layout item %@ doesn't respond to -setContentSize:", self);
	}
}

/* Dummy methods to shut down compiler warning about ETLayoutingContext not 
   fully implemented */

- (NSSize) size
{
	return [super size];
}

- (void) setSize: (NSSize)size
{
	[super setSize: size];
}

- (NSView *) view
{
	return [super view];
}

/* Live Development */

- (void) beginEditingUI
{
	/* Notify view and decorator item chain */
	[super beginEditingUI];
	
	/* Notify children */
	[[self items] makeObjectsPerformSelector: @selector(beginEditingUI)];
}

/* Deprecated (DO NOT USE, WILL BE REMOVED LATER) */

- (id) initWithLayoutItems: (NSArray *)layoutItems view: (NSView *)view value: (id)value representedObject: (id)repObject
{
	return [self initWithItems: layoutItems view: view value: value representedObject: repObject];
}

- (id) initWithLayoutItems: (NSArray *)layoutItems view: (NSView *)view
{
	return [self initWithItems: layoutItems view: view];
}

@end