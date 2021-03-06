/*
	Copyright (C) 2007 Quentin Mathe

	Author:  Quentin Mathe <qmathe@club-internet.fr>
	Date:  May 2007
	License: Modified BSD (see COPYING)
 */

#import <EtoileFoundation/NSIndexPath+Etoile.h>
#import <EtoileFoundation/NSObject+Etoile.h>
#import <EtoileFoundation/NSObject+HOM.h>
#import <EtoileFoundation/NSObject+Model.h>
#import <EtoileFoundation/ETUTI.h>
#import <EtoileFoundation/Macros.h>
#import "ETLayoutItem.h"
#import "ETActionHandler.h"
#import "ETBasicItemStyle.h"
#import "ETGeometry.h"
#import "ETInspector.h"
#import "ETLayoutItemGroup.h"
#import "ETLayoutItem+KVO.h"
#import "ETLayoutItem+Reflection.h"
#import "ETLayoutItem+Scrollable.h"
#import "EtoileUIProperties.h"
#import "ETScrollableAreaItem.h"
#import "ETStyleGroup.h"
#import "ETView.h"
#import "ETWindowItem.h"
#import "NSImage+Etoile.h"
#import "NSView+Etoile.h"
#import "ETCompatibility.h"

/* Notifications */
NSString *ETLayoutItemLayoutDidChangeNotification = @"ETLayoutItemLayoutDidChangeNotification";

#define DETAILED_DESCRIPTION
/* Don't forget that -variableProperties creates the property dictionary */
#define VARIABLE_PROPERTIES ((NSMutableDictionary *)[self variableProperties])

@interface ETLayoutItem (Private)
- (void) setViewAndSync: (NSView *)newView;
- (NSRect) bounds;
- (void) setBoundsSize: (NSSize)size;
- (NSPoint) centeredAnchorPoint;
@end

@implementation ETLayoutItem

static BOOL showsBoundingBox = NO;
static BOOL showsFrame = NO;

/** Returns whether the bounding box is drawn.

When YES, the receiver draws its bounding box as a red stroked rect. */
+ (BOOL) showsBoundingBox
{
	return showsBoundingBox;
}

/** Sets whether the bounding box is drawn.

See also -showsBoundingBox. */
+ (void) setShowsBoundingBox: (BOOL)shows
{
	showsBoundingBox = shows;
}

/** Returns whether the frame is drawn.

When YES, the receiver draws its frame as a blue stroked rect. */
+ (BOOL) showsFrame
{
	return showsFrame;
}

/** Sets whether the frame is drawn.

See also -showsFrame. */
+ (void) setShowsFrame: (BOOL)shows
{
	showsFrame = shows;
}

/* Initialization */

/** You must use -[ETLayoutItemFactory item] or -[ETLayoutItemFactory itemGroup] 
rather than this method.

Initializes and returns a layout item.

The returned item will use +defaultItemRect as its frame. */
- (id) init
{
	return [self initWithView: nil value: nil representedObject: nil];
}

/** <init />
You must use -[ETLayoutItemFactory itemXXX] or 
-[ETLayoutItemFactory itemGroupXXX] methods rather than this method.

Initializes and returns a layout item with the given view, value object and 
represented object. 

Any of the arguments can be nil.

When the given view is nil, the returned item will use +defaultItemRect as its 
frame.

See also -setView:, -setValue: and -setRepresentedObject:.  */
- (id) initWithView: (NSView *)view value: (id)value representedObject: (id)repObject
{
    SUPERINIT

	// TODO: Examine common use cases and see whether we should pass a 
	// capacity hint to improve performances.
	_variableProperties = [[NSMutableDictionary alloc] init];
	_defaultValues = [[NSMutableDictionary alloc] init];

	_parentItem = nil;

	[self setRepresentedObject: repObject];
	[self setValue: value];

	_styleGroup = [[ETStyleGroup alloc] init];
	[self setCoverStyle: [ETBasicItemStyle sharedInstance]];	
	[self setActionHandler: [ETActionHandler sharedInstance]];

	ASSIGN(_transform, [NSAffineTransform transform]);
	 /* Will be overriden by -setView: when the view is not nil */
	_autoresizingMask = NSViewNotSizable;
	_contentAspect = ETContentAspectStretchToFill;
	_boundingBox = ETNullRect;

	NSRect frame = (nil != view ? [view frame] : [[self class] defaultItemRect]);
	/* We must have a valid frame to use -setDefaultFrame:, otherwise this 
	   method will look up an invalid frame and try to restore it. */
	[self setFrame: frame];
	[self setDefaultFrame: frame];
	[self setViewAndSync: view];

	[self setFlipped: YES]; /* -setFlipped: must follow -setSupervisorView: */
	_visible = YES;

    return self;
}

/** <override-dummy />
Removes the receiver as an observer on all objects that it was observing until 
now.

You must override this method when a subclass calls KVO methods such as 
-addObserver:XXX. In the overriden method, you must call the superclass 
implementation.<br />
You must never call this method in your own code.

In -dealloc, we must stop to be a KVO observer immediately, otherwise we may 
receive KVO notifications triggered by releasing objects we observe. In the 
worst case, we can be retained/released and thereby reenter -dealloc. */
- (void) stopKVOObservation
{
	[_representedObject removeObserver: self];

	NSView *view = [self view];

	if (nil != view && [view isWidget])
	{
		[[(id <ETWidget>)view cell] removeObserver: self forKeyPath: @"objectValue"];
		[[(id <ETWidget>)view cell] removeObserver: self forKeyPath: @"state"];
	}
}

/** <override-never /> 
See -[ETLayoutItem dealloc]. */
- (void) stopKVOObservationIfNeeded
{
	/* This is not really pretty, but it makes possible to have the safest and 
	   simplest API semantic when a developer writes an ETLayoutItem subclass 
	   and want to add/remove observers. The deveveloper won't have to check 
	   special cases (e.g. was KVO stopped by a subclass) in -stopKVOObservation.
	   Later we could reuse this solution in other class hierarchy too, unless 
	   we figure out a better way to implement that. */
	if (_wasKVOStopped)
		return;

	[self stopKVOObservation];

	_wasKVOStopped = YES;
}

/** <override-dummy />
You must call -stopKVOObservationIfNeeded right at the beginning of -dealloc in 
every subclass that overrides -dealloc. */
- (void) dealloc
{
	[self stopKVOObservationIfNeeded];

	DESTROY(_variableProperties);
	DESTROY(_defaultValues);
	DESTROY(_styleGroup);
	DESTROY(_coverStyle);
	DESTROY(_representedObject);
	DESTROY(_transform);
	_parentItem = nil; /* weak reference */
    
    [super dealloc];
}

/** Returns a shallow copy of the receiver without copying the view, the styles, 
	the represented object and the children items if the receiver is an 
	ETLayoutItemGroup related classes. 
	Take note that a deep copy of the decorators is created and no view 
	reference is kept, -view will return nil for the copied item.
	TODO: Implement decorators copying that is currently missing.
	
Default values will be copied but not individually (shallow copy). */
- (id) copyWithZone: (NSZone *)aZone
{
	ETLayoutItem *item = [super copyWithZone: aZone];

	item->_variableProperties = [[NSMutableDictionary alloc] init];
	item->_defaultValues = [_defaultValues mutableCopyWithZone: aZone];

	// NOTE: Geometry synchronization logic in setters such as setFlippedView: 
	// and -setAutoresizingMask: is not required to make a copy, because all 
	// the related objects (supervisor view, decorator etc.) are in a valid and 
	// well synchronized state at copy time.
	// -[ETUIItem copyWithZone:] copies the supervisor view and its subviews
	
	/* We copy all object ivars except _parentItem */

	[item setRepresentedObject: [self representedObject]]; /* Will set up the observer */
	/* We set the style in the copy by copying the style group */
	item->_styleGroup = [_styleGroup copyWithZone: aZone];
	item->_coverStyle = RETAIN(_coverStyle);
	item->_transform = [_transform copyWithZone: aZone];

	/* We copy every primitive ivars except _isSyncingSupervisorViewGeometry */

	item->_contentBounds = _contentBounds;
	/* anchorPoint must be initialized before position but after contentBounds.
	   position must be initialized after anchorPoint. */
	SET_OBJECT_PROPERTY(item, GET_PROPERTY(kETAnchorPointProperty), kETAnchorPointProperty);
	item->_position = _position;
	/* Will be overriden by -setView: when the view is not nil */	
	item->_autoresizingMask = _autoresizingMask;
	item->_boundingBox = _boundingBox;
	item->_flipped = _flipped;
	item->_selected = _selected;
	item->_visible = _visible;
	item->_contentAspect = _contentAspect;
	item->_scrollViewShown = _scrollViewShown;

	/* We copy all variables properties except kETTargetProperty */

	SET_OBJECT_PROPERTY_AND_RELEASE(item, [GET_PROPERTY(kETValueProperty) copyWithZone: aZone], kETValueProperty);
	SET_OBJECT_PROPERTY(item, GET_PROPERTY(kETDefaultFrameProperty),  kETDefaultFrameProperty);
	SET_OBJECT_PROPERTY(item, GET_PROPERTY(kETNameProperty), kETNameProperty);
	SET_OBJECT_PROPERTY(item, GET_PROPERTY(kETImageProperty), kETImageProperty);
	SET_OBJECT_PROPERTY(item, GET_PROPERTY(kETIconProperty), kETIconProperty);
	SET_OBJECT_PROPERTY(item, GET_PROPERTY(kETSubtypeProperty),  kETSubtypeProperty);
	SET_OBJECT_PROPERTY(item, GET_PROPERTY(kETActionHandlerProperty), kETActionHandlerProperty);
	SET_OBJECT_PROPERTY(item, GET_PROPERTY(kETActionProperty), kETActionProperty);

	/* We adjust targets and observers to reference equivalent objects in the object graph copy */

	NSView *viewCopy = [item->supervisorView wrappedView];
	// NOTE: -objectForKey: returns nil when the key is nil.
	id target = [self target];
	id targetCopy = [[self objectReferencesForCopy] objectForKey: target];
	id viewTarget = [[[self view] ifResponds] target];
	id viewTargetCopy = [[self objectReferencesForCopy] objectForKey: viewTarget];

	if (nil == targetCopy)
	{
		targetCopy = target;
	} 
	if (nil == viewTargetCopy)
	{
		viewTargetCopy = viewTarget;
	}
	[[viewCopy ifResponds] setTarget: viewTargetCopy];
	[item setTarget: targetCopy];

	if ([viewCopy isWidget]) /* See -setView:autoresizingMask and keep in sync */
	{
		[[(id <ETWidget>)viewCopy cell] addObserver: item
		                                 forKeyPath: @"objectValue"
			                            options: NSKeyValueObservingOptionNew
		                                    context: NULL];
		[[(id <ETWidget>)viewCopy cell] addObserver: item
		                                 forKeyPath: @"state"
			                            options: NSKeyValueObservingOptionNew
		                                    context: NULL];
	}
	
	return item;
}

- (id) deepCopy
{
	return [self deepCopyWithZone: NSDefaultMallocZone()];
}

/** Returns a deep copy of the receiver by copying the view and all its 
	subview hierarchy, the styles, the decorators, the represented object and 
	all the descendant children items if the receiver is an ETLayoutItemGroup r
	elated classes. 
	All copied collections are mutable (styles, decorators, representedObject, 
	children items). 
	TODO: Implement styles copying that is currently missing (decorators too in 
	-copyWithZone:). */
- (id) deepCopyWithZone: (NSZone *)aZone
{
	ETLayoutItem *item = [self copyWithZone: aZone];

#if 0
	id repObjectCopy = nil;

	// TODO: We probably want to handle different kind of copies on the model. 
	// For example, with values objects a shallow copy of an array is a bad 
	// idea, so would be a deep copy for an array of entity objects.
	// A good solution may be to override -copyWithZone: and/or 
	// -mutableCopyWithZone: in collection classes to map each 
	// element based on its model description to a particular copy operation:
	// - value object -> copy
	// - entity object -> don't copy 
	// In this way, we could handle copy in a more meaningful way without having 
	// to decide between only the two crude copy styles deep and shallow. To 
	// achieve we need a model description (metamodel) framework like Magritte.
	// We still need to decide what should the default between shallow and deep 
	// for the represented object (model) when no model description is available.
	if ([[self representedObject] conformsToProtocol: @protocol(NSMutableCopying)])
	{
		repObjectCopy = [[self representedObject] mutableCopy];
	}
	else if ([[self representedObject] conformsToProtocol: @protocol(NSCopying)])
	{
		repObjectCopy = [[self representedObject] copy];
	}
	[item setRepresentedObject: AUTORELEASE(repObjectCopy)];
#endif

	return item;
}

static NSMapTable *objectRefsForCopy = nil;

/** Returns a context which binds objects/values in the original object graph to 
their new equivalent objects/values in the resulting copy. 

This context is a key/value table which allows to retrieve arbitrary objects 
(usually they are controller) that were copied by an ancestor layout item in the 
deep copy underway.
e.g. In an item copy, you can correct a reference to a controller that belongs 
to an ancestor item like that: 
<example>
id controllerInItemCopy = [[self objectReferencesForCopy] objectForKey: [self target]];

if (controllerInItemCopy != nil)
{
	ASSIGN(itemCopy->_target, controllerInItemCopy);
}
else
{
	ASSIGN(itemCopy->_target, _target);
}
</example> */
- (NSMapTable *) objectReferencesForCopy
{
	if (nil == objectRefsForCopy)
	{
		ASSIGN(objectRefsForCopy, [NSMapTable mapTableWithStrongToStrongObjects]);
	}
	return objectRefsForCopy;
}

- (NSString *) description
{
	NSString *desc = [super description];

#ifdef DETAILED_DESCRIPTION	
	desc = [@"<" stringByAppendingFormat: @"%@ meta: %d id: %@, ipath: %@, "
		@"selected: %d, repobject: %@ view: %@ frame %@>", desc, [self UIMetalevel], 
		[self identifier], [[self indexPath] keyPath], [self isSelected], 
		[[self representedObject] primitiveDescription], [self view], 
		NSStringFromRect([self frame])];
#else
	desc = [@"<" stringByAppendingFormat: @"%@ id: %@, selected:%d>", 
		desc, [self identifier], [self isSelected]];
#endif
	
	return desc;
}

/** Returns the root item of the layout item tree to which the receiver belongs 
to. 

This method never returns nil. The returned value is equal to self when the 
receiver has no parent item. */
- (id) rootItem
{
	if (_parentItem != nil)
	{
		return [_parentItem rootItem];	
	}
	else
	{
		return self;
	}
}

/** Returns the layout item group which controls the receiver.<br />
An item group is said to be base item that controls its descendant items when 
its represented path base is neither nil nor a blank value (see 
-hasValidRepresentedPathBase).

For every descendant item under its control, the base item will drive:
<list>
<item>pick and drop validation</item>
<item>source access</item>
</list>
Various delegate-like methods use the base item as their main argument.

All descendant items are controlled by the receiver base item until a descendant 
becomes a new base item (by providing a represented path base).<br /> 
See also -representedPathBase, -representedPath, -[ETLayoutItemGroup source] 
and related setter methods.

An item group is automatically turned into a base item, when you set a source 
or a controller (see -[ETLayoutItemGroup setController:]).

This method will return nil when the receiver isn't a base item or has no 
ancestor which is a base item.<br />
Hence -[[[ETLayoutItem alloc] init] baseItem] returns nil. */
- (ETLayoutItemGroup *) baseItem
{
	if ([self hasValidRepresentedPathBase])
	{
		return (ETLayoutItemGroup *)self;
	}
	else
	{
		return [_parentItem baseItem];
	}
}

/** Returns whether the receiver is a base item or not.

To be a base itemn the receiver must have a valid represented path base set. 
See -setRepresentedPathBase:. */
- (BOOL) isBaseItem
{
	return [self hasValidRepresentedPathBase];
}

/** Returns whether the current -representedPathBase value is valid to qualify 
the receiver as a base item. */
- (BOOL) hasValidRepresentedPathBase
{
	return ([self representedPathBase] != nil 
		&& [[self representedPathBase] isEqualToString: @""] == NO);
}

/** Returns the layout item group to which the receiver belongs to. 

For the root item, returns nil. */
- (ETLayoutItemGroup *) parentItem
{
	return _parentItem;
}

/** Sets the layout item group to which the receiver belongs to. 

If the given parent is nil, the receiver becomes a root item. 

You must never call this method directly, unless you write a subclass.<br />
To change the parent, use -addItem:, -removeFromParent and other similar methods 
to manipulate the item collection that belongs to the parent. */
- (void) setParentItem: (ETLayoutItemGroup *)parent
{
	//ETDebugLog(@"For item %@ with supervisor view %@, modify the parent item from "
	//	"%@ to %@", self, [self supervisorView], _parentItem, parent, self);
	NSParameterAssert(parent != self);
	_parentItem = parent;
}

/** Detaches the receiver from the item group it belongs to.

You are in charge of retaining the receiver, otherwise it could be deallocated 
if no other objects retains it. */
- (void ) removeFromParent
{
	if (_parentItem != nil)
	{
		/* -removeItem: will release us, so to be sure we won't deallocated 
		   right now we use retain/autorelease */
		RETAIN(self);
		[_parentItem removeItem: self];
		AUTORELEASE(self);
	}
}

/** Returns the first layout item bound to a view upwards in the layout item 
tree. 

The receiver itself can be returned. */
- (ETLayoutItem *) supervisorViewBackedAncestorItem
{
	if ([self displayView] != nil)
		return self;

	if (_parentItem != nil)
	{
		return [_parentItem supervisorViewBackedAncestorItem];
	}
	else
	{
		return nil;
	}
}

/** Returns the first display view bound to a layout item upwards in the layout 
item tree. This item is identical to the one returned by 
-supervisorViewBackedAncestorItem. 

The receiver display view itself can be returned. */
- (ETView *) enclosingDisplayView
{
	ETView *displayView = [self displayView];

	if (displayView != nil)
		return displayView;

	if (_parentItem != nil)
	{
		return [_parentItem enclosingDisplayView];
	}
	else
	{
		return nil;
	}
}

/** Returns the first layout item decorated by a window upwards in the layout 
item tree. 

The receiver itself can be returned. */
- (id) windowBackedAncestorItem
{
	NSWindow *window = [[[self supervisorViewBackedAncestorItem] supervisorView] window];

	if (nil == window)
		return nil;

	// FIXME: Should be ok to use (but not with ObjectManagerExample... we have 
	// need to turn the window into a window item sooner to eliminate the crash 
	//in -awakeFromNib)
	//NSParameterAssert([[window contentView] isSupervisorView]);
	if ([[window contentView] isSupervisorView] == NO)
		return nil;

	return [[[window contentView] layoutItem] firstDecoratedItem];
}

/** Returns receiver index path relative to the given item. 

The index path is computed by climbing up the layout item tree until we 
find the given item. At each level we traverse, the parent relative index is 
pushed into the index path to be returned. 

Passing nil is equivalent to passing the root item.<br />
If the given item is equal to self, the resulting index path is a blank one 
(relative to itself). */
- (NSIndexPath *) indexPathFromItem: (ETLayoutItem *)item
{
	NSIndexPath *indexPath = nil;
	BOOL baseItemReached = (self == item);

	/* Handle nil item case which implies root item is the base item */
	if (item == nil && self == [self rootItem])
		baseItemReached = YES;
	
	if (_parentItem != nil && item != self)
	{
		indexPath = [_parentItem indexPathFromItem: item];
		if (indexPath != nil)
		{
			indexPath = [indexPath indexPathByAddingIndex: 
				[(ETLayoutItemGroup *)_parentItem indexOfItem: (id)self]];
		}
	}
	else if (baseItemReached)
	{
		indexPath = [NSIndexPath indexPath];
	}

	/* We return a nil index path only if we haven't reached the base item */   	
	return indexPath;
}

/** Returns the given item index path relative to the receiver.

This method is equivalent to [item indexFromItem: self].

Returns nil when the given item isn't a receiver descendant.

Passing nil is equivalent to passing the root item. In this case, the returned 
value is nil because the root item can never be a receiver descendant.<br />
If the given item is equal to self, the resulting index path is an blank one 
(relative to itself). */
- (NSIndexPath *) indexPathForItem: (ETLayoutItem *)item
{
	return [item indexPathFromItem: self];
}

/** Returns the receiver absolute index path by collecting the index of each
parent item until the root item is reached (when -parentItem returns nil). 

This method is equivalent to [[self rootItem] indexPathForItem: self]. */
- (NSIndexPath *) indexPath
{
	// TODO: Test whether it is worth to optimize or not
	return [[self rootItem] indexPathForItem: self];
}

/** Returns the receiver absolute path by collecting the name of each parent 
item until the root item is reached (when -parentItem returns nil). 

This method is equivalent to 
[[self rootItem] pathForIndexPath: [[self rootItem] indexPathForItem: self]]. */
- (NSString *) path
{
	/* We rebuild the path by chaining names of the layout item tree to which 
	   we belong. */
	NSString *path = @"/";
	
	if (_parentItem != nil)
	{
		path = [[_parentItem path] 
			stringByAppendingPathComponent: [self identifier]];
	}
	
	return path;
}

/** Returns the represented path which is built with the represented path base 
provided by the base item. */
- (NSString *) representedPath
{
	NSString *path = [self representedPathBase];
	
	if (path == nil)
	{
		if (_parentItem != nil)
		{
			path = [_parentItem representedPath];
			path = [path stringByAppendingPathComponent: [self identifier]];
		}
		else
		{
			path = [self identifier];
		}
	}
	
	return path;
}

/** Returns the represented path base. By default, returns nil.

With a represented path base, an ETLayoutItemGroup instance becomes a base 
item, and its descendant items will use this path base to build their 
represented paths (see -representedPath). This path base is valid until a 
represented path base is set on a descendant and as such becomes a base item.
See -[ETLayoutItemGroup setRepresentedPathBase:].

Represented paths are relative to the base item unlike paths returned by -path 
which are absolute paths. */
- (NSString *) representedPathBase
{
	return GET_PROPERTY(kETRepresentedPathBaseProperty);
}

/** Returns the identifier associated with the layout item. By default, returns 
the name.

If -name returns nil or an empty string, the identifier is a string made of 
the index used by the parent item to reference the receiver. */
- (NSString *) identifier
{
	NSString *identifier = [self name];
	
	if (identifier == nil || [identifier isEqual: @""])
	{
		id parentRepObject = [_parentItem representedObject];
		
		// TODO: Should try to retrieve -UniqueID, -UUID and -UUIDString and 
		// simplify the if conditional.
		/* -identifierAtIndex: is implemented by some classes like NSDictionary */
		if ([parentRepObject isCollection] && [parentRepObject isEmpty] == NO
		 && [parentRepObject respondsToSelector: @selector(identifierAtIndex:)]
		 && [_parentItem usesRepresentedObjectAsProvider])
		{
			unsigned int index = [_parentItem indexOfItem: self];
			identifier = [parentRepObject identifierAtIndex: index];
		}
	}

	/*if (identifier == nil || [identifier isEqual: @""])	
		identifier = [self name];*/

	if (identifier == nil || [identifier isEqual: @""])
	{
		identifier = [NSString stringWithFormat: @"%d", 
			[(ETLayoutItemGroup *)_parentItem indexOfItem: (id)self]];
	}
	
	return identifier;
}

/** Returns the display name associated with the receiver. See also 
NSObject(Model) in EtoileFoundation. */
- (NSString *) displayName
{
	id name = [self name];
	
	if (name == nil)
	{
		if ([self view] != nil)
		{
			name = [[self view] description];
		}
		else if ([self value] != nil)
		{
			name = [[self value] stringValue];
		}
		else if ([self representedObject] != nil)
		{
			/* Makes possible to keep an identical display name between an 
			   item and all derived meta items (independently of their meta 
			   levels). */
			name = [[self representedObject] displayName];
		}
		else
		{
			name = [super displayName];
		}
	}
		
	return name;
}

/** Sets the name associated with the receiver with -setName:. */
- (void) setDisplayName: (NSString *)aName
{
	[self setName: aName];
}

/** Returns the name associated with the layout item.
 
The returned value can be nil or an empty string. */
- (NSString *) name
{
	return GET_PROPERTY(kETNameProperty);
}

/** Sets the name associated with the layout item. */
- (void) setName: (NSString *)name
{
	SET_PROPERTY(name, kETNameProperty);
}

/** Returns a value object, that can be used when a single property has to be 
displayed. See also -setValue:. */
- (id) value
{
	return GET_PROPERTY(kETValueProperty);
}

/** Sets a value object.<br />
Styles or layouts can use it to show the receiver with a basic value 
representation or when they restrict their presentation to a single property.

e.g. a table layout with a single column or a simple positional layout where 
ETBasicItemStyle will try to draw the value. To know how the value can be 
presented, see ETLayout and ETStyle subclasses.

The value object is typically a string, a number or an image.

If the represented object declares a property 'value', both 
[receiver valueForProperty: @"value"] and 
[receiver setValue: anObject forProperty: @"value"] won't access your value 
object but the one provided by the represented object. */
- (void) setValue: (id)value
{
	// TODO: Should we restrict what values can be accepted...
	/*if ([value isCommonObjectValue] == NO)
	{
		[NSException raise: NSInvalidArgumentException format: @"Value %@ must "
			@"be a common object value to be set in %@", value, self];
		return;
	}*/
	
	SET_PROPERTY(value, kETValueProperty);
}

/** Returns the model object which embeds the data to be displayed and 
represented on screen by the receiver. See also -setRepresentedObject:. */
- (id) representedObject
{
	return _representedObject;
}

/** Returns the represented object when not nil, otherwise returns the receiver.

You shouldn't have to use this method a lot since -valueForProperty: and 
-setValue:forProperty: make the property access transparent. For example 
[self valueForProperty: kNameProperty] is equivalent to [[self subject] name].

-subject can be useful with KVC which only considers the layout item itself. e.g. 
[itemCollection valueForKey: @"subject.name"].  */
- (id) subject
{
	return (nil != _representedObject ? _representedObject : (id)self);
}

- (void) syncView: (NSView *)aView withValue: (id)newValue
{
	if (nil == aView || NO == [aView isWidget])
		return;

	[(id <ETWidget>)aView setObjectValue: newValue];
}

/* -value is not implemented by every object unlike -objectValue which is implemented 
by NSObject+Model in EtoileFoundation. */
- (void) syncView: (NSView *)aView withRepresentedObject: (id)anObject
{
	if (nil == anObject)
		return;

	id value = nil;

	if ([anObject respondsToSelector: @selector(value)])
	{
		value = [anObject value];
	}
	else
	{
		value = [anObject objectValue];
	}

	[self syncView: aView withValue: value];
}

/** Sets the model object which embeds the data to be displayed and represented 
on screen by the receiver.

Take note modelObject can be any objects including an ETLayoutItem instance, in 
this case the receiver becomes a meta item and returns YES for -isMetaLayoutItem.

The item view is also synchronized with the object value of the given represented 
object when the view is a widget. */
- (void) setRepresentedObject: (id)modelObject
{
	id oldObject = _representedObject;

	[_representedObject removeObserver: self];

	/* To ensure the values are not released before the KVO notification ends */
	RETAIN(oldObject);	
	NSSet *affectedKeys = [self willChangeRepresentedObjectFrom: oldObject 
	                                                         to: modelObject];
	ASSIGN(_representedObject, modelObject);
	[self didChangeValuesForKeys: affectedKeys];
	RELEASE(oldObject);

	[self syncView: [self view] withRepresentedObject: modelObject];
	[modelObject addObserver: self];
}

- (ETView *) setUpSupervisorViewWithFrame: (NSRect)aFrame 
{
	if (supervisorView != nil)
		return supervisorView;

	/* Will call back -setSupervisorView:sync: which retains the view */
	supervisorView = [[ETView alloc] initWithFrame: aFrame item: self];
	RELEASE(supervisorView);
	return supervisorView;
}

- (unsigned int) autoresizingMaskForContentAspect: (ETContentAspect)anAspect
{
	switch (anAspect)
	{
		case ETContentAspectNone:
		case ETContentAspectComputed:
		{
			return ETAutoresizingNone;
		}
		case ETContentAspectCentered:
		{
			return ETAutoresizingFlexibleLeftMargin | ETAutoresizingFlexibleRightMargin 
				| ETAutoresizingFlexibleBottomMargin | ETAutoresizingFlexibleTopMargin;
		}
		case ETContentAspectScaleToFill:
		case ETContentAspectScaleToFillHorizontally:
		case ETContentAspectScaleToFillVertically:
		case ETContentAspectScaleToFit:
		{
			// TODO: May be return ETAutoresizingCustom or ETAutoresizingProportional
			return ETAutoresizingNone;		
		}
		case ETContentAspectStretchToFill:
		{
			return ETAutoresizingFlexibleWidth | ETAutoresizingFlexibleHeight;
		}
		default:
		{
			ASSERT_INVALID_CASE;
			return ETAutoresizingNone;
		}
	}
}

- (NSRect) contentRectWithRect: (NSRect)aRect 
                 contentAspect: (ETContentAspect)anAspect 
                    boundsSize: (NSSize)maxSize
{
	switch (anAspect)
	{
		case ETContentAspectNone:
		{
			return aRect;
		}
		case ETContentAspectCentered:
		{
			return ETCenteredRect(aRect.size, ETMakeRect(NSZeroPoint, maxSize));
		}
		case ETContentAspectComputed:
		{
			return [[self coverStyle] rectForViewOfItem: self];
		}
		case ETContentAspectScaleToFill:
		case ETContentAspectScaleToFillHorizontally:
		case ETContentAspectScaleToFillVertically:
		case ETContentAspectScaleToFit:
		{
			return ETScaledRect(aRect.size, ETMakeRect(NSZeroPoint, maxSize), anAspect);	
		}
		case ETContentAspectStretchToFill:
		{
			return ETMakeRect(NSZeroPoint, maxSize);
		}
		default:
		{
			ASSERT_INVALID_CASE;
			return ETNullRect;
		}
	}
}

/** Tries to resize the item view with -sizeToFit, then adjusts the receiver 
content size to match the view size. */
- (void) sizeToFit
{
	ETContentAspect contentAspect = [self contentAspect];

	/* To prevent -setContentSize: to resize the view when it resizes the 
	   supervisor view. */
	[self setContentAspect: ETContentAspectNone];
	[[[self view] ifResponds] sizeToFit];
	[self setContentSize: [[self view] frame].size];
	[self setContentAspect: contentAspect];
}

/** Returns the view associated with the receiver. */
- (NSView *) view
{
	return [[self supervisorView] wrappedView];
}

	/* When the view isn't an ETView instance, we wrap it inside a new ETView 
	   instance to have -drawRect: asking the layout item to render by itself.
	   Retrieving the display view automatically returns the innermost display
	   view in the decorator item chain. */
- (void) setView: (NSView *)newView autoresizingMask: (ETAutoresizing)autoresizing
{
	NSView *oldView = [supervisorView wrappedView];
	BOOL stopObservingOldView = (nil != oldView && [oldView isWidget]);
	BOOL startObservingNewView = (nil != newView && [newView isWidget]);

	if (stopObservingOldView)
	{
		[[(id <ETWidget>)oldView cell] removeObserver: self forKeyPath: @"objectValue"];
		[[(id <ETWidget>)oldView cell] removeObserver: self forKeyPath: @"state"];
	}

	/* Insert a supervisor view if needed and adjust the new view autoresizing behavior */
	if (nil != newView)
	{
		[self setUpSupervisorViewWithFrame: [self frame]];
		NSParameterAssert(NSEqualSizes([self contentBounds].size, [supervisorView frame].size));

		[newView setAutoresizingMask: autoresizing];
		/* The view frame will be adjusted by -[ETView tileContentView:temporary:]
		   which invokes -contentRectWithRect:contentAspect:boundsSize:. */
	}

	[supervisorView setWrappedView: newView];
	[self syncView: newView withRepresentedObject: _representedObject]; 

	if (startObservingNewView)
	{
		[[(id <ETWidget>)newView cell] addObserver: self 
		                                forKeyPath: @"objectValue"
		                                   options: NSKeyValueObservingOptionNew
	                                           context: NULL];
		[[(id <ETWidget>)newView cell] addObserver: self 
		                                forKeyPath: @"state"
		                                   options: NSKeyValueObservingOptionNew
		                                   context: NULL];
	}
}

/** Sets the view associated with the receiver. This view is commonly a widget 
provided by the widget backend. 

The receiver autoresizing mask will be updated to match the given view, and 
the default frame and frame to match this view frame. */
- (void) setViewAndSync: (NSView *)newView
{
	if (newView != nil)
	{
		// NOTE: Frame and autoresizing are lost when newView is inserted into the 
		// supervisor view.
		NSRect newViewFrame = [newView frame];
		unsigned int newViewAutoresizing = [newView autoresizingMask];

		[self setUpSupervisorViewWithFrame: newViewFrame];
		NSParameterAssert(nil != [self supervisorView]);

		[self setContentAspect: ETContentAspectStretchToFill];
		[self setDefaultFrame: newViewFrame];
		// FIXME: Convert to ETAutoresizing by checking -isFlipped.
		[self setAutoresizingMask: newViewAutoresizing];
	}
	[self setView: newView autoresizingMask: [self autoresizingMaskForContentAspect: [self contentAspect]]];
}

/** Sets the view associated with the receiver. This view is commonly a widget 
provided by the widget backend. */
- (void) setView: (NSView *)newView
{
	[self setView: newView autoresizingMask: [self autoresizingMaskForContentAspect: [self contentAspect]]];
}

/** Returns whether the view used by the receiver is a widget. 

Also returns YES when the receiver uses a layout view which is a widget 
provided by the widget backend. See -[ETLayout layoutView].

See also -[NSView(Etoile) isWidget]. */
- (BOOL) usesWidgetView
{
	// NOTE: The next line would work too...
	//return ([self view] != nil || [[[self layout] layoutView] isWidget]);
	return ([[self view] isWidget] || [[[self layout] layoutView] isWidget]);
}

/* Key Value Coding */

- (id) valueForUndefinedKey: (NSString *)key
{
	//ETLog(@"NOTE: -valueForUndefinedKey: %@ called in %@", key, self);
	return GET_PROPERTY(key); /* May return nil */
}

- (void) setValue: (id)value forUndefinedKey: (NSString *)key
{
	//ETLog(@"NOTE: -setValue:forUndefinedKey: %@ called in %@", key, self);
	SET_PROPERTY(value, key);
}

/* Property Value Coding */

/** Returns a value of the model object -representedObject, usually by calling
-valueForProperty: on the represented object. If the represented object is a 
layout item, -valueForKey: will be  called instead of -valueForProperty:. 

-valueForProperty: is implemented by NSObject as part of the 
ETPropertyValueCoding informal protocol. When the represented object is a custom 
model object, it must override -valueForProperty: and -setValue:forProperty: or 
conform to NSKeyValueCoding protocol. See ETPropertyValueCoding to understand 
how to implement your model object.

When the represented object is a layout item, the receiver is a meta layout item 
(see -isMetaItem and -[NSObject(ETLayoutItem) isLayoutItem]). */
- (id) valueForProperty: (NSString *)key
{
	id modelObject = [self representedObject];
	id value = nil;

	/* Basic version which doesn't fetch property value beyond the represented 
	   object, even if this represented object represents another object too. */
	if (modelObject != nil && [[(NSObject *)modelObject properties] containsObject: key])
	{
		if ([modelObject isLayoutItem])
		{
			value = [modelObject valueForKey: key];
		}
		else
		{
			/* We  cannot use -valueForKey here because many classes such as 
			   NSArray, NSDictionary etc. overrides KVC accessors with their own 
			   semantic. */
			value = [modelObject valueForProperty: key];
		}
	}
	else
	{
		value = [self valueForKey: key];
	}	
	
	return value;
}

/** Sets a value identified by key of the model object returned by 
-representedObject. 

See -valueForProperty: for more details. */
- (BOOL) setValue: (id)value forProperty: (NSString *)key
{
	id modelObject = [self representedObject];
	BOOL result = YES;

	/* Basic version which doesn't propagate property editing beyond the represented 
	   object, even if this represented object represents another object too. */
	if (modelObject != nil && [[(NSObject *)modelObject properties] containsObject: key])
	{
		if ([modelObject isLayoutItem])
		{
			[modelObject setValue: value forKey: key];
		}
		else
		{
			/* We  cannot use -setValue:forKey here because many classes such as 
			   NSArray, NSDictionary etc. overrides KVC accessors with their own 
			   semantic. */
			result = [modelObject setValue: value forProperty: key];
		}
	}
	else
	{
		[self setValue: value forKey: key];
	}
	
	// FIXME: Implement
	//[self didChangeValueForKey: key];
	
	return result;
}

- (NSArray *) properties
{
	NSArray *properties = A(kETIdentifierProperty, kETNameProperty, kETXProperty, kETYProperty, 
		kETWidthProperty, kETHeightProperty, kETViewProperty, kETSelectedProperty, 
		kETLayoutProperty, kETStyleGroupProperty, kETStyleProperty, 
		kETCoverStyleProperty, kETImageProperty, kETFrameProperty, 
		kETRepresentedObjectProperty, kETRepresentedPathBaseProperty, 
		kETParentItemProperty, kETAutoresizingMaskProperty, 
		kETBoundingBoxProperty, kETActionProperty, kETSubtypeProperty, 
		kETTargetProperty, kETUIMetalevelProperty, @"UIMetalayer");

	properties = [[VARIABLE_PROPERTIES allKeys] arrayByAddingObjectsFromArray: properties];
		
	return [[super properties] arrayByAddingObjectsFromArray: properties];
}

/** Returns a dictionary representation of every property/value pairs not stored 
in ivars.
 
Unless you write a subclass or reflection code, you should never need this 
method, but use the property accessors or Property Value Coding methods to read 
and write the receiver properties. */
- (NSDictionary *) variableProperties
{
	return _variableProperties;
}

/** Returns YES, see [NSObject(EtoileUI) -isLayoutItem] */
- (BOOL) isLayoutItem
{
	return YES;
}

/** Returns NO, see -[ETLayoutItemGroup isGroup] */
- (BOOL) isGroup
{
	return NO;
}

/** Sets the receiver selection state.

You rarely need to call this method. You should rather use -setSelectionIndex:, 
-setSelectionIndexes: or -setSelectionIndexPaths: on the parent item (see 
ETLayoutItemGroup).

This method doesn't post an ETItemGroupSelectionDidChangeNotification unlike 
the previously mentioned ETLayoutItemGroup methods.

The new selection state won't be apparent until a redisplay occurs. */
- (void) setSelected: (BOOL)selected
{
	if (selected == _selected)
		return;

	[self willChangeValueForKey: kETSelectedProperty];
	_selected = selected;
	ETDebugLog(@"Set layout item selection state %@", self);
	[self didChangeValueForKey: kETSelectedProperty];
}

/** Returns the receiver selection state. See also -setSelected:. */
- (BOOL) isSelected
{
	return _selected;
}

- (BOOL) canBecomeVisible
{
	return ([[self layout] isOpaque] == NO);
}

/** Sets whether the receiver should be displayed or not.

The new visibility state won't be apparent until a redisplay occurs. 

When the layout changes, this receiver visibility might change. Any custom 
value you might have set is lost too and won't be restored by switching back to 
the previous layout in use. */
- (void) setVisible: (BOOL)visible
{
	_visible = visible;
	if (visible)
	{
		[_parentItem handleAttachViewOfItem: self];
		ETDebugLog(@"Inserted view at %@", NSStringFromRect([self frame]));
	}
	else
	{
		[_parentItem handleDetachViewOfItem: self];
		ETDebugLog(@"Removed view at %@", NSStringFromRect([self frame]));
	}
}

/** Returns whether the receiver should be displayed or not. See also -setVisible:. */
- (BOOL) isVisible
{
	return _visible;
}

/** Returns the receiver UTI type as -[NSObject UTI], but combines it with the
subtype and the represented object type when available.

When the receiver has a subtype, the returned type is a transient type whose 
supertypes are the class type and the subtype.<br />
When the receiver has a represented object, the returned type is a transient 
type whose supertypes are the class type and the represented object class type.<br />
In case, the receiver has both a represented object and a subtype, the 
returned type will combine both as supertypes. */
- (ETUTI *) UTI
{
	ETUTI *subtype = [self subtype];
	NSMutableArray *supertypes = [NSMutableArray arrayWithObject: [super UTI]];

	if (subtype != nil)
	{
		[supertypes addObject: subtype];
	}
	if (_representedObject != nil)
	{
		[supertypes addObject: [_representedObject UTI]];
	}

	return [ETUTI transientTypeWithSupertypes: supertypes];
}

/** Sets the receiver subtype.

This method can be used to subtype an object (without involving any subclassing).

You can use it to restrict pick and drop allowed types to the receiver type, 
when the receiver is a "pure UI object" without a represented object bound to it. */
- (void) setSubtype: (ETUTI *)aUTI
{
	/* Check type aggressively in case the user passes a string */
	NSParameterAssert([aUTI isKindOfClass: [ETUTI class]]);
	SET_PROPERTY(aUTI, kETSubtypeProperty);
}

/** Returns the receiver subtype.

More explanations in -setSubtype. See also -type. */
- (ETUTI *) subtype
{
	return GET_PROPERTY(kETSubtypeProperty);
}

/* Returns the supervisor view associated with the receiver. The supervisor view 
is a wrapper view around the receiver view (see -view). 

You shouldn't use this method unless you write a subclass.

The supervisor view is used internally by EtoileUI to support views or widgets 
provided by the widget backend (e.g. AppKit) within a layout item tree. See 
also ETView. */
- (ETView *) supervisorView
{
	return supervisorView;
}

/** Sets the supervisor view associated with the receiver. 

You should never need to call this method.

The view will be added as a subview to the supervisor view bound to the 
parent item to which the given item belongs to. Which means, this method may 
move the view to a different place in the view hierarchy.

Throws an exception when item parameter is nil.

See also -supervisorView:. */
- (void) setSupervisorView: (ETView *)aSupervisorView sync: (ETSyncSupervisorView)syncDirection
{
	if (nil != aSupervisorView)
	{
		if (ETSyncSupervisorViewToItem == syncDirection)
		{
			[self setFrame: [aSupervisorView frame]];
			[self setAutoresizingMask: [aSupervisorView autoresizingMask]];
		}
		else /* ETSyncSupervisorViewFromItem */
		{
			[aSupervisorView setFrame: [self frame]];
			[aSupervisorView setAutoresizingMask: [self autoresizingMask]];
		}
	}

	[super setSupervisorView: aSupervisorView sync: syncDirection];

	BOOL noDecorator = (_decoratorItem == nil);
	BOOL hasParent = (_parentItem != nil);
	
	if (noDecorator && hasParent)
	{
		[_parentItem handleAttachViewOfItem: self];
	}
}

/* Inserts a supervisor view that is required to be decorated. */
- (void) setDecoratorItem: (ETDecoratorItem *)decorator
{
	BOOL needsInsertSupervisorView = (decorator != nil);
	if (needsInsertSupervisorView)
	{
		[self setUpSupervisorViewWithFrame: [self frame]];
	}
	[super setDecoratorItem: decorator];
}

/** When the receiver content is presented inside scrollers, returns the 
decorator item that owns the scrollers provided by the widget backend (e.g. 
AppKit), otherwise returns nil.

When multiple scrollable area items are present in the decorator chain, the 
first is returned.

Won't return an enclosing scrollable area item bound to an ancestor item. */
- (ETScrollableAreaItem *) scrollableAreaItem
{
	id decorator = self;
	
	while ((decorator = [decorator decoratorItem]) != nil)
	{
		if ([decorator isKindOfClass: [ETScrollableAreaItem class]])
			break;
	}
	
	return decorator;
}

/** When the receiver content is presented inside a window, returns the 
decorator item that owns the window provided by the widget backend (e.g. 
AppKit), otherwise returns nil.

Won't return an enclosing window item bound to an ancestor item.<br />
To retrieve the enclosing window item, use 
[[self windowBackedAncestorItem] windowItem]. */
- (ETWindowItem *) windowItem
{
	id lastDecorator = [self lastDecoratorItem];
	id windowDecorator = nil;
	
	if ([lastDecorator isKindOfClass: [ETWindowItem class]])
		windowDecorator = lastDecorator;
		
	return windowDecorator;
}

/** <override-never />
Tells the receiver the layout has been changed and it should post 
ETLayoutItemLayoutDidChangeNotification. 

This method tries to notify the delegate that might exist with subclasses 
e.g. ETLayoutItemGroup.

You should never use this method unless you write an ETLayoutItem subclass. */
- (void) didChangeLayout: (ETLayout *)oldLayout
{
	[[self layout] syncLayoutViewWithItem: self];
	[self updateScrollableAreaItemVisibility];

	/* We must not let the tool attached to the old layout remain active, 
	   otherwise the layout can be deallocated and this tool remains with an 
	   invalid -layoutOwner. */
	ETTool *oldTool = [oldLayout attachedTool];

	if ([oldTool isEqual: [ETTool activeTool]])
	{
		ETTool *newTool = [[self layout] attachedTool];

		if (newTool == nil)
		{
			newTool = [ETTool mainTool];
		}
		[ETTool setActiveTool: newTool];
	}

	/* Notify the interested parties about the layout change */
	NSNotification *notif = [NSNotification 
		notificationWithName: ETLayoutItemLayoutDidChangeNotification object: self];
	id delegate = [self valueForKey: kETDelegateProperty];

	if ([delegate respondsToSelector: @selector(layoutDidChange:)])
		[delegate layoutDidChange: notif];
	
	[[NSNotificationCenter defaultCenter] postNotification: notif];
}

/** Returns the layout associated with the receiver to present its content. */
- (id) layout
{
	return GET_PROPERTY(kETLayoutProperty);
}

/** Sets the layout associated with the receiver to present its content.

Layout are not yet supported on ETLayoutItem instances, which this method is 
useless currently. */
- (void) setLayout: (ETLayout *)aLayout
{
	ETLayout *oldLayout = GET_PROPERTY(kETLayoutProperty);
	RETAIN(oldLayout);
	SET_PROPERTY(aLayout, kETLayoutProperty);
	[self didChangeLayout: oldLayout];
	RELEASE(oldLayout);
}

/** Returns the topmost ancestor layout item, including itself, whose layout 
returns YES to -isOpaque (see ETLayout). If none is found, returns self. */
- (ETLayoutItem *) ancestorItemForOpaqueLayout
{
	ETLayoutItem *parent = self;
	ETLayoutItem *lastFoundOpaqueAncestor = self;

	while (parent != nil)
	{
		if ([[parent layout] isOpaque])
			lastFoundOpaqueAncestor = parent;
		
		parent = [parent parentItem];
	}

	return lastFoundOpaqueAncestor;
}

/** <override-dummy />
Forces the layout to be recomputed to take in account geometry and content 
related changes since the last layout update.

This method is not yet implemented.<br />
See also -[ETLayoutItemGroup updateLayout].  */
- (void) updateLayout
{
	// TODO: Implement
}

static inline NSRect DrawingBoundsInWindowItem(ETWindowItem *windowItem)
{
	/* We exclude the window border and title bar because the display 
	   view is the window content view and never the window view. */
	return ETMakeRect(NSZeroPoint, [windowItem contentRect].size);
}

/* Returns the drawing bounds for the cover style.

You can draw outside of the drawing bounds in the limits of the drawing box.
The drawing box used a negative origin expressed relatively to the drawing 
bounds origin. */
- (NSRect) drawingBounds
{
	ETWindowItem *windowItem = [self windowItem];
	NSRect rect;

	if (nil != windowItem)
	{
		rect = DrawingBoundsInWindowItem(windowItem);
	}
	else
	{
		rect = [self bounds];
	}

	return rect;
}

/** Returns the bounds where the given style is expected to draw the item.

When the style is the cover style, the drawing area is enclosed in the item 
frame.<br />
When the style is a content style that belongs to -styleGroup, the drawing area 
is enclosed in the item content bounds (which might be partially clipped by 
a decorator).

When no decorator is set on the receiver, returns the same rect usually.

For example, we have an item with boundingBox = { -10, -10, 170, 220 } and 
frame = { 30, 40, 150, 200 }, then in an ETStyle subclass whose instances would 
receive this item through -render:layoutItem:dirtyRect:
<example>
// bounds.origin is the current drawing context origin
NSRect bounds = [item drawingBoundsForStyle: self]; 
NSRect box = [item boundingBox];

[NSBezierPath fillRect: bounds]; // bounds is { 0, 0, 150, 200 }
// With a custom bounding box, you can draw outside of the drawing bounds
[NSBezierPath strokeRect: box]; // box is { -10, -10, 170, 220 }
</example> 

See also -contentBounds, -frame, -boundingBox, -coverStyle, -styleGroup and 
-style. */
- (NSRect) drawingBoundsForStyle: (ETStyle *)aStyle
{
	BOOL isCoverStyle = (aStyle == _coverStyle);

	return (isCoverStyle ? [self drawingBounds] : _contentBounds);
}

/** This method is only exposed to be used internally by EtoileUI.

Returns the -coverStyle drawing area (i.e. the clipping rect).

The returned rect is the bouding box but adjusted to prevent drawing on the 
window decorations. */
- (NSRect) drawingBox
{
	ETWindowItem *windowItem = [self windowItem];
	NSRect rect;

	if (nil != windowItem)
	{
		rect = DrawingBoundsInWindowItem(windowItem);
	}
	else
	{
		rect = [self boundingBox];
	}

	return rect;
}

/** This method is only exposed to be used internally by EtoileUI.

Returns the -styleGroup visible drawing area (i.e. the clipping rect).

The returned rect is the visible content bounds. */
- (NSRect) contentDrawingBox
{
	return [self visibleContentBounds];
}

- (void) drawFrameWithRect: (NSRect)aRect
{
	[[NSColor blueColor] setStroke];
	[NSBezierPath setDefaultLineWidth: 1.0];
	[NSBezierPath strokeRect: aRect];
}

- (void) drawBoundingBoxWithRect: (NSRect)aRect
{
	[[NSColor redColor] setStroke];
	[NSBezierPath setDefaultLineWidth: 1.0];
	[NSBezierPath strokeRect: aRect];
}

/* For debugging */
- (void) drawViewItemMarker
{
	if ([self displayView] == nil)
		return;

	[[NSColor greenColor] set];
	[NSBezierPath setDefaultLineWidth: 3.0];
	[NSBezierPath strokeRect: [self bounds]];
}

/** <override-dummy />
Renders or draws the receiver in the given rendering context. 

The rendering is entirely delegated to the style group.<br />
Subclasses such as ETLayoutItemGroup can override this method to extend, alter 
or replace this behavior.

EtoileUI will lock and unlock the focus when needed around this method, unless 
you call this method directly. In this case, you are responsible to lock/unlock 
the focus.

You are allowed to draw beyond the receiver frame (EtoileUI doesn't clip the 
drawing). In that case, you have to use -setBoundingBox to specify the area were 
the redisplay is now expected to occur, otherwise methods like -display and 
-setNeedsDisplay: won't work correctly.<br />
You should be careful and only use this possibility to draw visual 
embellishments strictly related to the receiver. e.g. borders, selection mark, 
icon badge, control points etc.

dirtyRect indicates the receiver portion that needs to be redrawn and is 
expressed in the receiver coordinate space. This rect is is usally equal to 
-drawingFrame. But it can be smaller when the parent item doesn't need to be 
entirely redrawn and the portion to redraw intersects the receiver area 
(without covering it).<br />
Warning: When -decoratorItem is not nil, the receiver coordinate space is not  
equal to the receiver content coordinate space.

inputValues is a key/value pair list that is initially passed to the ancestor 
item on which the rendering was started. You can add or remove key/value pairs  
to let styles know how they are expected to be rendered.<br />
This key/value pair list will be carried downwards until the rendering is finished.

ctxt represents the rendering context which encloses the drawing context. For 
now, the context is nil and must be ignored.  */
- (void) render: (NSMutableDictionary *)inputValues 
      dirtyRect: (NSRect)dirtyRect 
      inContext: (id)ctxt 
{
	//ETLog(@"Render frame %@ of %@ dirtyRect %@ in %@", 
	//	NSStringFromRect([self drawingFrame]), self, NSStringFromRect(dirtyRect), ctxt);
	BOOL reponsibleToDrawCoverStyle = (nil == _decoratorItem);

	[[self styleGroup] render: inputValues layoutItem: self dirtyRect: dirtyRect];

	/* When we have no decorator, the cover style is rendered here, otherwise the 
	   last decorator renders it (see -[ETDecoratorItem render:dirtyRect:inContext:). */
	if (reponsibleToDrawCoverStyle)
	{
		[NSGraphicsContext saveGraphicsState];
		[[NSBezierPath bezierPathWithRect: dirtyRect] setClip];
		[_coverStyle render: inputValues layoutItem: self dirtyRect: dirtyRect];
		[NSGraphicsContext restoreGraphicsState];
	}

	//[self drawViewItemMarker];
	if (showsBoundingBox)
	{
		[self drawBoundingBoxWithRect: [self boundingBox]];
	}
	if (showsFrame)
	{
		[self drawFrameWithRect: [self bounds]];
	}
}

/** Marks the receiver and the entire layout item tree owned by it to be 
redisplayed the next time an ancestor view receives a display if needed 
request (see -[NSView displayIfNeededXXX] methods). 

More explanations in -display. */
- (void) setNeedsDisplay: (BOOL)flag
{
	[self setNeedsDisplayInRect: [self convertRectToContent: [self boundingBox]]];
}

/** Marks the given receiver area and the entire layout item subtree that 
intersects it, to be redisplayed the next time an ancestor view receives a 
display if needed request (see -[NSView displayIfNeededXXX] methods). 

More explanations in -display. */
- (void) setNeedsDisplayInRect: (NSRect)dirtyRect
{
	NSView *displayView = nil;
	NSRect displayRect = [[self firstDecoratedItem] convertDisplayRect: dirtyRect 
	                        toAncestorDisplayView: &displayView
							rootView: [[[self enclosingDisplayView] window] contentView]
							parentItem: _parentItem];

	[displayView setNeedsDisplayInRect: displayRect];
}

/** Triggers the redisplay of the receiver and the entire layout item tree 
owned by it. 

To handle the display, an ancestor view is looked up and the rect to refresh is 
converted into this ancestor coordinate space. Precisely both the lookup and the 
conversion are handled by 
-convertDisplayRect:toAncestorDisplayView:rootView:parentItem:.

If the receiver has a display view, this view will be asked to draw by itself.  */
- (void) display
{
	 /* Redisplay the content bounds unless a custom bouding box is set */
	[self displayRect: [self convertRectToContent: [self boundingBox]]];
}

/** Triggers the redisplay of the given receiver area and the entire layout item 
subtree that intersects it. 

More explanations in -display. */
- (void) displayRect: (NSRect)dirtyRect
{
	// NOTE: We could also use the next two lines to redisplay, but 
	// -convertDisplayRect:toAncestorDisplayView: is more optimized.
	//ETLayoutItem *ancestor = [self supervisorViewBackedAncestorItem];
	//[[ancestor displayView] displayRect: [self convertRect: [self boundingBox] toItem: ancestor]];

	NSView *displayView = nil;
	NSRect displayRect = [[self firstDecoratedItem] convertDisplayRect: dirtyRect
	                        toAncestorDisplayView: &displayView
							rootView: [[[self enclosingDisplayView] window] contentView]
							parentItem: _parentItem];
	[displayView displayRect: displayRect];
}

/** Redisplays the areas marked as invalid in the receiver and all its descendant 
items.

Areas can be marked as invalid with -setNeedsDisplay: and -setNeedsDisplayInRect:. */
- (void) displayIfNeeded
{
	[[self enclosingDisplayView] displayIfNeeded];
}

/** When the receiver is visible in an opaque layout and won't redraw by itself, 
marks the ancestor item to redisplay the area that corresponds to the receiver 
in this layout. Else marks the receiver to be redisplayed exactly as 
-setNeedsDisplay: with YES. 

See also -ancestorItemForOpaqueLayout. */
- (void) refreshIfNeeded
{
	ETLayoutItem *opaqueAncestor = [self ancestorItemForOpaqueLayout];

	if (opaqueAncestor != self)
	{
		[[opaqueAncestor layout] setNeedsDisplayForItem: self];
	}
	else
	{
		[self setNeedsDisplay: YES];
	}
}

/** Returns the style group associated with the receiver. By default, 
returns a style group whose only style element is an ETBasicItemStyle object. */    
- (ETStyleGroup *) styleGroup
{
	return _styleGroup;
}

/** Sets the style group associated with the receiver.

The styles inside the style group control the drawing of the receiver.<br />
See ETStyle to understand how to customize the layout item look. */
- (void) setStyleGroup: (ETStyleGroup *)aStyle
{
	ASSIGN(_styleGroup, aStyle);
}

/** Returns the first style inside the style group. */
- (id) style
{
	return [[self styleGroup] firstStyle];
}

/** Removes all styles inside the style group, then adds the given style to the 
style group. 

If the given style is nil, the style group becomes empty. */
- (void) setStyle: (ETStyle *)aStyle
{
	[[self styleGroup] removeAllStyles];
	if (aStyle != nil)
	{
		[[self styleGroup] addStyle: aStyle];
	}
}

- (id) coverStyle
{
	return _coverStyle;
}

- (void) setCoverStyle: (ETStyle *)aStyle
{
	ASSIGN(_coverStyle, aStyle);
}

- (void) setDefaultValue: (id)aValue forProperty: (NSString *)key
{
	[_defaultValues setObject: aValue forKey: key];
}

- (id) defaultValueForProperty: (NSString *)key
{
	return [_defaultValues objectForKey: key];
}

/* Geometry */

/** Returns a rect expressed in the parent item content coordinate space 
equivalent to rect parameter expressed in the receiver coordinate space. */
- (NSRect) convertRectToParent: (NSRect)rect
{
	NSRect rectToTranslate = rect;
	NSRect rectInParent = rect;

	if ([self isFlipped] != [_parentItem isFlipped])
	{
		rectToTranslate.origin.y = [self height] - rect.origin.y - rect.size.height;
	}

	// NOTE: See -convertRectFromParent:...
	// NSAffineTransform *transform = [NSAffineTransform transform];
	// [transform translateXBy: [self x] yBy: [self y]];
	// rectInParent.origin = [transform transformPoint: rect.origin];
	rectInParent.origin.x = rectToTranslate.origin.x + [self x];
	rectInParent.origin.y = rectToTranslate.origin.y + [self y];
	
	return rectInParent;
}

/** Returns a rect expressed in the receiver coordinate space equivalent to
rect parameter expressed in the parent item content coordinate space. */
- (NSRect) convertRectFromParent: (NSRect)rect
{
	NSRect rectInReceiver = rect; /* Keep the size as is */

	// NOTE: If we want to handle bounds transformations (rotation, translation,  
	// and scaling), we should switch to NSAffineTransform, the current code 
	// would be...
	// NSAffineTransform *transform = [NSAffineTransform transform];
	// [transform translateXBy: -([self x]) yBy: -([self y])];
	// rectInChild.origin = [transform transformPoint: rect.origin];
	rectInReceiver.origin.x = rect.origin.x - [self x];
	rectInReceiver.origin.y = rect.origin.y - [self y];

	if ([self isFlipped] != [_parentItem isFlipped])
	{
		rectInReceiver.origin.y = [self height] - rectInReceiver.origin.y - rectInReceiver.size.height;
	}

	return rectInReceiver;
}

/** Returns a point expressed in the parent item content coordinate space 
equivalent to point parameter expressed in the receiver coordinate space. */
- (NSPoint) convertPointToParent: (NSPoint)point
{
	return [self convertRectToParent: ETMakeRect(point, NSZeroSize)].origin;
}

/** Returns a rect expressed in the receiver coordinate space equivalent to rect 
parameter expressed in ancestor coordinate space.

In case the receiver is not a descendent or ancestor is nil, returns a null rect. */
- (NSRect) convertRect: (NSRect)rect fromItem: (ETLayoutItemGroup *)ancestor
{
	if (self == ancestor)
		return rect;

	if (ETIsNullRect(rect) || ancestor == nil || _parentItem == nil)
		return ETNullRect;

	NSRect newRect = rect;

	if (_parentItem != ancestor)
	{
		newRect = [_parentItem convertRect: rect fromItem: ancestor];
	}

	return [self convertRectFromParent: [_parentItem convertRectToContent: newRect]];
}

/** Returns a rect expressed in ancestor coordinate space equivalent to rect 
parameter expressed in the receiver coordinate space.

In case the receiver is not a descendent or ancestor is nil, returns a null rect. */
- (NSRect) convertRect: (NSRect)rect toItem: (ETLayoutItemGroup *)ancestor
{
	if (ETIsNullRect(rect) || _parentItem == nil || ancestor == nil)
		return ETNullRect;

	NSRect newRect = rect;
	ETLayoutItem *parent = self;

	while (parent != ancestor)
	{
		newRect = [parent convertRectToParent: [parent convertRectFromContent: newRect]];
		parent = [parent parentItem];
	}

	return newRect;
}

/** Returns whether the receiver uses flipped coordinates to position its 
content. 
 
The returned value will be taken in account in methods related to geometry, 
event handling and drawing. If you want to alter the flipping, you must use 
-setFlipped: and never alter the supervisor view directly with 
-[ETView setFlipped:].  */
- (BOOL) isFlipped
{
	// TODO: Review ETLayoutItem hierarchy to be sure flipped coordinates are 
	// well supported.
	if (supervisorView != nil)
	{
		// TODO: Enable later...
		/*if (_flipped != [supervisorView isFlipped])
		{
			ETLog(@"WARNING: -isFlipped doesn't match between the layout item "
				"%@ and its supervisor view %@... You may have wrongly called "
				"-setFlipped: on the supervisor view.", supervisorView, self);
		}*/
		return [supervisorView isFlipped];
	}

	return _flipped;
}

/** Sets whether the receiver uses flipped coordinates to position its content. 

This method updates the supervisor view and the decorator chain to match the 
flipping of the receiver.

You must never alter the supervisor view directly with -[ETView setFlipped:]. */
- (void) setFlipped: (BOOL)flip
{
	if (flip == _flipped)
		return;

	_flipped = flip;
	[[self supervisorView] setFlipped: flip];
	[[self decoratorItem] setFlipped: flip];
}

/** Returns a point expressed in the receiver coordinate space equivalent to
point parameter expressed in the parent item content coordinate space. */
- (NSPoint) convertPointFromParent: (NSPoint)point
{
	return [self convertRectFromParent: ETMakeRect(point, NSZeroSize)].origin;
}

/** Returns whether a point expressed in the parent item content coordinate 
space is within the receiver frame. The item frame is also expressed in the 
parent item content coordinate space.
 
This method checks whether the parent item is flipped or not. */
- (BOOL) containsPoint: (NSPoint)point
{
	return NSMouseInRect(point, [self frame], [_parentItem isFlipped]);
}

/** Returns whether a point expressed in the receiver coordinate space is inside 
the receiver frame.

If the bounding box is used to test the point location, YES can be returned with 
a point whose y or x values are negative.  */
- (BOOL) pointInside: (NSPoint)point useBoundingBox: (BOOL)extended
{
	if (extended)
	{
		return NSMouseInRect(point, [self boundingBox], [self isFlipped]);	
	}
	else
	{
		return NSMouseInRect(point, [self bounds], [self isFlipped]);
	}
}

- (NSRect) bounds
{
	BOOL hasDecorator = (_decoratorItem != nil);
	NSRect rect = NSZeroRect;

	if (hasDecorator)
	{
		rect.size = [[self lastDecoratorItem] decorationRect].size;
	}
	else
	{
		rect.size = [self contentBounds].size;
	}

	return rect;
}

- (void) setBoundsSize: (NSSize)size
{
	BOOL hasDecorator = (_decoratorItem != nil);

	if (hasDecorator)
	{
		/* Will indirectly resize the supervisor view with -setFrameSize: that 
		   will in turn call back -setContentSize:. */
		[[self lastDecoratorItem] setDecorationRect: ETMakeRect([self origin], size)];
	}
	else
	{
		[self setContentSize: size];
	}
}

/** Returns the persistent frame associated with the receiver. 

This custom frame is used by ETFreeLayout. This property keeps track of the 
fixed location and size that are used for the receiver in the free layout, even 
if you switch to another layout that alters the receiver frame. The current 
frame is returned by -frame in all cases, hence when ETFreeLayout is in use, 
-frame is equal to -persistentFrame. */
- (NSRect) persistentFrame
{
	// TODO: Find the best way to eventually allow the represented object to 
	// provide and store the persistent frame.
	NSValue *value = GET_PROPERTY(kETPersistentFrameProperty);
	
	/* -rectValue wrongly returns random rect values when value is nil */
	if (value == nil)
		return ETNullRect;

	return [value rectValue];
}

/** Sets the persistent frame associated with the receiver. See -persistentFrame. */
- (void) setPersistentFrame: (NSRect) frame
{
	SET_PROPERTY([NSValue valueWithRect: frame], kETPersistentFrameProperty);
}

- (void) updatePersistentGeometryIfNeeded
{
	ETLayout *parentLayout = [_parentItem layout];

	if ([parentLayout isPositional] && [parentLayout isComputedLayout] == NO)
		[self setPersistentFrame: [self frame]];
}

/** Returns the current frame. If the receiver has a view attached to it, the 
returned frame is equivalent to the display view frame.  

This value is always in sync with the persistent frame in a positional and 
non-computed layout such as ETFreeLayout, but is usually different when the 
layout is computed.<br />
See also -setPersistentFrame: */
- (NSRect) frame
{
	BOOL hasDecorator = (_decoratorItem != nil);

	if (hasDecorator)
	{
		return [[self lastDecoratorItem] decorationRect];
	}
	else
	{
		return ETMakeRect([self origin], [self contentBounds].size);
	}
}

/** Sets the current frame and also the persistent frame if the layout of the 
parent item is positional and non-computed such as ETFreeLayout.

See also -[ETLayout isPositional] and -[ETLayout isComputedLayout]. */
- (void) setFrame: (NSRect)rect
{
	NSParameterAssert(_isSyncingSupervisorViewGeometry == NO);

	ETDebugLog(@"-setFrame: %@ on %@", NSStringFromRect(rect), self); 

	BOOL hasDecorator = (_decoratorItem != nil);

	if (hasDecorator)
	{
		/* Will indirectly resize the supervisor view with -setFrameSize: that 
		   will in turn call back -setContentSize:. */
		[[self lastDecoratorItem] setDecorationRect: rect];
		[[self coverStyle] didChangeItemBounds: ETMakeRect(NSZeroPoint, rect.size)];
	}
	else
	{
		[self setContentSize: rect.size];
	}
	/* Must follow -setContentSize: to allow the anchor point to be computed */
	 // TODO: When the receiver is decorated, will invoke -setDecorationRect: 
	 // one more time. We should eliminate this extra call.
	[self setOrigin: rect.origin];
}

/** Returns the current origin associated with the receiver frame. See also -frame. */
- (NSPoint) origin
{
	NSPoint anchorPoint = [self anchorPoint];
	NSPoint origin = [self position];

	origin.x -= anchorPoint.x;
	origin.y -= anchorPoint.y;

	return origin;
}

/** Sets the current origin associated with the receiver frame. See also -setFrame:. */   
- (void) setOrigin: (NSPoint)origin
{
	NSPoint anchorPoint = [self anchorPoint];
	NSPoint position = origin ;

	position.x += anchorPoint.x;
	position.y += anchorPoint.y;

	[self setPosition: position];
}

/** Returns the current anchor point associated with the receiver content bounds. 
The anchor point is expressed in the receiver content coordinate space.

By default, the anchor point is centered in the content bounds rectangle. See 
-contentBounds.

The item position is relative to the anchor point. See -position. */
- (NSPoint) anchorPoint
{
	if (HAS_PROPERTY(kETAnchorPointProperty) == NO)
	{
		NSPoint anchor = [self centeredAnchorPoint];
		SET_PROPERTY([NSValue valueWithPoint: anchor], kETAnchorPointProperty);
		return anchor;
	}
	return [GET_PROPERTY(kETAnchorPointProperty) pointValue];
}

/* Returns the center of the bounds rectangle in the receiver content coordinate 
space. */
- (NSPoint) centeredAnchorPoint
{
	NSSize boundsSize = [self contentBounds].size;	
	NSPoint anchorPoint = NSZeroPoint;
	
	anchorPoint.x = boundsSize.width / 2.0;
	anchorPoint.y = boundsSize.height / 2.0;
	
	return anchorPoint;
}

/** Sets the current anchor point associated with the receiver content bounds. 
anchor must be expressed in the receiver content coordinate space. */  
- (void) setAnchorPoint: (NSPoint)anchor
{
	ETDebugLog(@"Set anchor point to %@ - %@", NSStringFromPoint(anchor), self);
	SET_PROPERTY([NSValue valueWithPoint: anchor], kETAnchorPointProperty);
}

/** Returns the current position associated with the receiver frame. The 
position is expressed in the parent item coordinate space. See also 
-setPosition:. */
- (NSPoint) position
{
	return _position;
}

- (BOOL) shouldSyncSupervisorViewGeometry
{
	return (_isSyncingSupervisorViewGeometry == NO && [self supervisorView] != nil);
}

/** Sets the current position associated with the receiver frame.

When -setPosition: is called, the position is applied relative to -anchorPoint. 
position must be expressed in the parent item coordinate space (exactly as the 
frame). When the position is set, the frame is moved to have the anchor point 
location in the parent item coordinate space equal to the new position value. */  
- (void) setPosition: (NSPoint)position
{
	_position = position;

	// NOTE: Will probably be reworked once layout item views are drawn directly by EtoileUI.
	if ([self shouldSyncSupervisorViewGeometry])
	{
		BOOL hasDecorator = (_decoratorItem != nil);
		
		_isSyncingSupervisorViewGeometry = YES;
		if (hasDecorator)
		{
			ETDecoratorItem *lastDecoratorItem = [self lastDecoratorItem];
			NSSize size = [lastDecoratorItem decorationRect].size;
			NSRect movedFrame = ETMakeRect([self origin], size);
			/* Will indirectly move the supervisor view with -setFrameOrigin: that 
			   will in turn call back -setOrigin:. */
			[lastDecoratorItem setDecorationRect: movedFrame];
		}
		else
		{
			[[self displayView] setFrameOrigin: [self origin]];
		}
		_isSyncingSupervisorViewGeometry = NO;
	}

	[self updatePersistentGeometryIfNeeded];
}

/** Returns the current size associated with the receiver frame. See also -frame. */       
- (NSSize) size
{
	return [self bounds].size;
}

/** Sets the current size associated with the receiver frame. See also -setFrame:. */           
- (void) setSize: (NSSize)size
{
	[self setBoundsSize: size];
}

/** Returns the current x coordinate associated with the receiver frame origin. 
See also -frame. */       
- (float) x
{
	return [self origin].x;
}

/** Sets the current x coordinate associated with the receiver frame origin. 
See also -setFrame:. */
- (void) setX: (float)x
{
	[self setOrigin: NSMakePoint(x, [self y])];
}

/** Returns the current y coordinate associated with the receiver frame origin. 
See also -frame. */
- (float) y
{
	return [self origin].y;
}

/** Sets the current y coordinate associated with the receiver frame origin. 
See also -setFrame:. */
- (void) setY: (float)y
{
	[self setOrigin: NSMakePoint([self x], y)];
}

/** Returns the current height associated with the receiver frame size. See also 
-frame. */
- (float) height
{
	return [self size].height;
}

/** Sets the current height associated with the receiver frame size. See also 
-setFrame:. */
- (void) setHeight: (float)height
{
	[self setSize: NSMakeSize([self width], height)];
}

/** Returns the current width associated with the receiver frame size. See also 
-frame. */
- (float) width
{
	return [self size].width;
}

/** Sets the current width associated with the receiver frame size. See also 
-setFrame:. */
- (void) setWidth: (float)width
{
	[self setSize: NSMakeSize(width, [self height])];
}

/** Returns the content bounds associated with the receiver. */
- (NSRect) contentBounds
{
	return _contentBounds;
}

/** Returns the content bounds expressed in the decorator item coordinate space. 
When no decorator is set, the parent item coordinate space is used.

Both decoration rect and content bounds have the same size, because the first 
decorated item is never a decorator and thereby has no decoration. */ 
- (NSRect) decorationRectForContentBounds: (NSRect)bounds
{
	BOOL hasDecorator = (_decoratorItem != nil);

	if (hasDecorator)
	{
		return ETMakeRect([_decoratorItem contentRect].origin, bounds.size);
	}
	else
	{
		return ETMakeRect([self origin], bounds.size);
	}
}

/* Used by ETDecoratorItem */
- (NSRect) decorationRect
{
	return [self decorationRectForContentBounds: [self contentBounds]];
}

/** Sets the content bounds associated with the receiver.

By default, the origin of the content bounds is (0.0, 0.0). You can customize it 
to translate the coordinate system used to draw the receiver. The receiver 
transform, which might include a translation too, won't be altered. Both 
translations are cumulative.

If the flipped property is modified, the content bounds remains identical. */
- (void) setContentBounds: (NSRect)rect
{
	_contentBounds = rect;

	if ([self shouldSyncSupervisorViewGeometry])
	{
		BOOL hasDecorator = (_decoratorItem != nil);
		
		_isSyncingSupervisorViewGeometry = YES;
		if (hasDecorator)
		{
			NSRect decorationRect = [self decorationRectForContentBounds: [self contentBounds]];
			_contentBounds.size = [_decoratorItem decoratedItemRectChanged: decorationRect];
		}
		else
		{
			[[self displayView] setFrameSize: _contentBounds.size];
		}
		_isSyncingSupervisorViewGeometry = NO;
	}

	[self updatePersistentGeometryIfNeeded];
	[[self styleGroup] didChangeItemBounds: _contentBounds];
}

/** Sets the content size associated with the receiver. */
- (void) setContentSize: (NSSize)size
{
	[self setContentBounds: ETMakeRect([self contentBounds].origin, size)];
}

/** Returns a rect expressed in the receiver coordinate space equivalent 
to rect parameter expressed in the receiver content coordinate space.

The content coordinate space is located inside -contentBounds. */
- (NSRect) convertRectFromContent: (NSRect)rect
{
	id decorator = [self decoratorItem];
	NSRect rectInFrame = rect;

	while (decorator != nil)
	{
		rectInFrame = [decorator convertDecoratorRectFromContent: rectInFrame];
		decorator = [decorator decoratorItem];
	} 

	return rectInFrame;
}

/** Returns a rect expressed in the receiver content coordinate space 
equivalent to rect parameter expressed in the receiver coordinate space.

The content coordinate space is located inside -contentBounds. */
- (NSRect) convertRectToContent: (NSRect)rect
{
	id decorator = [self lastDecoratorItem];
	NSRect rectInContent = rect;

	while (decorator != self)
	{
		rectInContent = [decorator convertDecoratorRectToContent: rectInContent];
		decorator = [decorator decoratedItem];
	} 

	return rectInContent;
}

/** Returns a point expressed in the receiver content coordinate space 
equivalent to point parameter expressed in the receiver coordinate space.

The content coordinate space is located inside -contentBounds. */
- (NSPoint) convertPointToContent: (NSPoint)aPoint
{
	return [self convertRectToContent: ETMakeRect(aPoint, NSZeroSize)].origin;
}

/** Sets the transform applied within the content bounds. */
- (void) setTransform: (NSAffineTransform *)aTransform
{
	ASSIGN(_transform, aTransform);
}

/** Returns the transform applied within the content bounds. */
- (NSAffineTransform *) transform
{
	return _transform;
}

/** This method is only exposed to be used internally by EtoileUI.

Returns the visible portion of the content bounds when the receiver content is 
clipped by a decorator, otherwise the same than -contentBounds.

The returned rect is expressed in the receiver content coordinate space. */
- (NSRect) visibleContentBounds
{
	NSRect visibleContentBounds = [self contentBounds];

	if (nil != _decoratorItem)
	{
		visibleContentBounds = [_decoratorItem visibleRect];
	}
	else
	{
		visibleContentBounds.origin = NSZeroPoint;
	}

	return visibleContentBounds;
}

/** Returns the rect that fully encloses the receiver and represents the maximal 
extent on which hit test is done and redisplay requested. This rect is expressed 
in the receiver content coordinate space.

You must be cautious with the bounding box, since its value is subject to be 
overwritten by the layout in use. See -setBoundingBox:. */
- (NSRect) boundingBox
{
	if (ETIsNullRect(_boundingBox))
		return [self bounds];

	return _boundingBox;
}

/** Sets the rect that fully encloses the receiver and represents the maximal 
extent on which hit test is done and redisplay requested. This rect must be 
expressed in the receiver coordinate space.

The bounding box is used by ETTool in the hit test phase. It is also used 
by -display and -setNeedsDisplay: methods to compute the dirty area that needs 
to be refreshed. Hence it can be used by ETLayout subclasses related code to 
increase the area which requires to be redisplayed. For example, ETHandleGroup 
calls -setBoundingBox: on its manipulated object, because its handles are not 
fully enclosed in the receiver frame.

The bounding box must be always be greater or equal to the receiver frame. */
- (void) setBoundingBox: (NSRect)extent
{
	_boundingBox = extent;
}

/** Returns the default frame associated with the receiver. See -setDefaultFrame:. */
- (NSRect) defaultFrame 
{
	NSValue *value = GET_PROPERTY(kETDefaultFrameProperty);
	
	/* -rectValue wrongly returns random rect values when value is nil */
	if (value == nil)
		return ETNullRect;

	return [value rectValue]; 
}

/** Sets the default frame associated with the receiver and updates the item 
frame to match. The default frame is not touched by layout-related transforms 
(such as item scaling) unlike the item frame returned by -frame. 

When the layout item gets instantiated, the value is set to the initial item 
frame. */
- (void) setDefaultFrame: (NSRect)frame
{ 
	SET_PROPERTY([NSValue valueWithRect: frame], kETDefaultFrameProperty);
	/* Update display view frame only if needed */
	if (NSEqualRects(frame, [self frame]) == NO)
		[self restoreDefaultFrame];
}

/** Modifies the frame associated with the receiver to match the current default 
frame. */
- (void) restoreDefaultFrame
{ 
	[self setFrame: [self defaultFrame]]; 
}

/** Returns the autoresizing mask that applies to the layout item as whole. 

See also -setAutoresizingMask:.   */
- (ETAutoresizing) autoresizingMask
{
	return _autoresizingMask;
}

/** Sets the autoresizing mask that applies to the layout item as whole. 

The autoresizing mask only applies to the last decorator item (which might be 
the receiver itself).<br />
When the receiver has a decorator, the content autoresizing is controlled by the 
decorator and not by the receiver autoresizing mask directly.

TODO: Autoresizing mask isn't yet supported when the receiver has no view. */
- (void) setAutoresizingMask: (ETAutoresizing)aMask
{
	_autoresizingMask = aMask;

	if ([self shouldSyncSupervisorViewGeometry] == NO)
		return;
	
	_isSyncingSupervisorViewGeometry = YES;
	// TODO: Might be reduce to a single line with [super setAutoresizingMask: aMask];
	if (nil != _decoratorItem)
	{
		[[self lastDecoratorItem] setAutoresizingMask: aMask];
	}
	else
	{
		[[self supervisorView] setAutoresizingMask: aMask];
	}
	_isSyncingSupervisorViewGeometry = NO;
}

/** Returns that the content aspect that describes how the content looks when 
the receiver is resized.

See ETContentAspect enum. */
- (ETContentAspect) contentAspect
{
	return _contentAspect;
}

/** Sets the content aspect that describes how the content looks when the 
receiver is resized.

When the item has a view, the view autoresizing mask and frame are altered to 
match the new content aspect.

See ETContentAspect enum. */
- (void) setContentAspect: (ETContentAspect)anAspect
{
	_contentAspect = anAspect;

	if ([self view] != nil)
	{
		[[self view] setAutoresizingMask: [self autoresizingMaskForContentAspect: anAspect]];
		[[self view] setFrame: [self contentRectWithRect: [[self view] frame] 
		                                   contentAspect: anAspect 
		                                      boundsSize: _contentBounds.size]];
	}
}

/** Returns the image representation associated with the receiver.

By default this method, returns by decreasing order of priority:
<enum>
<item>the receiver image (aka ETImageProperty), if -setImage: was called previously</item>
<item>the receiver value, if -value returns an NSImage object</item>
<item>nil, if none of the above conditions are met</item>
</enum>.
The returned image can be overriden by calling -setImage:. 
 
See also -icon. */
- (NSImage *) image
{
	NSImage *img = GET_PROPERTY(kETImageProperty);
	
	if (img == nil && [[self value] isKindOfClass: [NSImage class]])
		img = [self value];
		
	return img;
}

/** Sets the image representation associated with the receiver.

The image is drawn by the styles based on the content aspect. See 
ETBasicItemStyle as an example.<br />
You can adjust the image size by altering the receiver size combined with a 
content aspect such as ETContentAspectScaleXXX or ETContentAspectStretchXXX. 

If img is nil, then the default behavior of -image is restored and the returned 
image should not be expected to be nil. */
- (void) setImage: (NSImage *)img
{
	SET_PROPERTY(img, kETImageProperty);
}

// NOTE: May be we should have -displayIcon (or -customIcon, -setCustomIcon:) to 
// eliminate the lack of symetry between -icon and -setIcon:.
/** Returns the image to be displayed when the receiver must be represented in a 
symbolic style. This icon is commonly used by some layouts and also if the 
receiver represents another layout item (when -isMetaLayoutItem returns YES).

By default, this method returns by decreasing order of priority:
<enum>
<item>the receiver icon (aka kETIconProperty), if -setIcon: was called previously</item>
<item>the receiver image (aka kETImageProperty), if -image doesn't return nil</item>
<item>the represented object icon, if the represented object and the icon 
associated with it are not nil</item>
<item>a receiver snapshot, if the item can be snapshotted</item>
<item>nil, if none of the above conditions are met</item>
</enum>. 
The returned image can be overriden by calling -setIcon:.

-image and -icon can be considered as symetric equivalents of -name and 
-displayName methods. */
- (NSImage *) icon
{
	NSImage *icon = GET_PROPERTY(kETIconProperty);
	
	if (icon == nil)
		icon = [self image];

	if (icon == nil && [self representedObject] != nil)
		icon = [[self representedObject] icon];

	if (icon == nil)
		icon = [self snapshotFromRect: [self bounds]];
		
	if (icon == nil)
	{
		ETDebugLog(@"Icon missing for %@", self);
	}
	
	return icon;
}

/** Sets the image to be displayed when the receiver must be represented in a 
symbolic style. See also -icon.

If img is nil, then the default behavior of -icon is restored and the icon image 
should not be expected to be nil. */
- (void) setIcon: (NSImage *)img
{
	SET_PROPERTY(img, kETIconProperty);
}

/** Returns an image snapshot of the receiver. The snapshot is taken at the time 
this method is called.

The given rect must be expressed in the receiver coordinate space.

When the receiver isn't backed by a window and has no window-backed ancestor 
item backed either, returns nil. */
- (NSImage *) snapshotFromRect: (NSRect)aRect
{
	id viewBackedItem = [self supervisorViewBackedAncestorItem];

	if (nil == viewBackedItem || nil == [[viewBackedItem supervisorView] window])
		return nil;

	NSRect rectInView = [self convertRect: aRect toItem: viewBackedItem];
	ETWindowItem *windowItem = [viewBackedItem windowItem];

	if (nil != windowItem)
	{
		/* We exclude the window border and title bar because the display 
		   view is the window content view and never the window view. */
		rectInView = [windowItem convertDecoratorRectToContent: rectInView];
	}

	return AUTORELEASE([[NSImage alloc] initWithView: [viewBackedItem displayView] fromRect: rectInView]);
}

- (NSAffineTransform *) boundsTransform
{
	NSAffineTransform *transform = [NSAffineTransform transform];

	if ([self isFlipped])
	{
		[transform translateXBy: 0.0 yBy: [self height]];
		[transform scaleXBy: 1.0 yBy: -1.0];
	}

	return transform;
}

- (void) drawRect: (NSRect)aRect
{
	if ([self supervisorView] != nil)
	{
		[[self displayView] displayRectIgnoringOpacity: aRect 
		                                     inContext: [NSGraphicsContext currentContext]];
	}
	else
	{
		NSAffineTransform *transform = [self boundsTransform];
		[transform concat];

		[self render: nil dirtyRect: aRect inContext: nil];

		[transform invert];
		[transform concat];
	}
}

/* Events & Actions */

/** Returns the action handler associated with the receiver. See ETTool to 
know more about event handling in the layout item tree. */
- (id) actionHandler
{
	return GET_PROPERTY(kETActionHandlerProperty);
}

/** Sets the action handler associated with the receiver. */
- (void) setActionHandler: (id)anHandler
{
	SET_PROPERTY(anHandler, kETActionHandlerProperty);
}

/** Returns NO when the receiver should be ignored by the tools for both 
hit tests and action dispatch. By default, returns YES, otherwise NO when 
-actionsHandler returns nil. */
- (BOOL) acceptsActions
{
	return (GET_PROPERTY(kETActionHandlerProperty) != nil);
}

/** Controls the automatic enabling/disabling of UI elements (such as menu 
items) that uses the responder chain to validate themselves, based on whether 
the receiver or its action handler can respond to the selector action that would 
be sent by the UI element in the EtoileUI responder chain. */
- (BOOL) validateUserInterfaceItem: (id <NSValidatedUserInterfaceItem>)anItem
{
// TODO: Remove when validation works correctly on GNUstep
#ifndef GNUSTEP
	SEL action = [anItem action];
	SEL twoParamSelector = NSSelectorFromString([NSStringFromSelector(action) 
		stringByAppendingString: @"onItem:"]);

	if ([self respondsToSelector: action])
		return YES;

	if ([[self actionHandler] respondsToSelector: twoParamSelector])
		return YES;

	return NO;
#endif
	return YES;
}

- (BOOL) respondsToSelector: (SEL)aSelector
{
	if ([super respondsToSelector: aSelector])
		return YES;
		
	SEL twoParamSelector = NSSelectorFromString([NSStringFromSelector(aSelector) 
		stringByAppendingString: @"onItem:"]);
	if ([[self actionHandler] respondsToSelector: twoParamSelector])
		return YES;

	return NO;
}

- (NSMethodSignature *) methodSignatureForSelector: (SEL)aSelector
{
	NSMethodSignature *sig = [super methodSignatureForSelector: aSelector];
	
	if (sig == nil)
	{
		SEL twoParamSelector = NSSelectorFromString([NSStringFromSelector(aSelector) 
		stringByAppendingString: @"onItem:"]);

		sig = [[self actionHandler] methodSignatureForSelector: twoParamSelector];
	}

	return sig;
}

- (void) forwardInvocation: (NSInvocation *)inv
{
	SEL selector = [inv selector];

	if ([self respondsToSelector: selector] == NO)
	{
		[self doesNotRecognizeSelector: selector];
		return;
	}

	SEL twoParamSelector = NSSelectorFromString([NSStringFromSelector(selector) 
		stringByAppendingString: @"onItem:"]);
	NSInvocation *twoParamInv = nil;
	id sender = nil;
	id actionHandler = GET_PROPERTY(kETActionHandlerProperty);
	
	[inv getArgument: &sender atIndex: 2];
	twoParamInv = [NSInvocation invocationWithMethodSignature: 
	[actionHandler methodSignatureForSelector: twoParamSelector]];
	[twoParamInv setSelector: twoParamSelector];
	[twoParamInv setArgument: &sender atIndex: 2];
	[twoParamInv setArgument: &self atIndex: 3];

	[twoParamInv invokeWithTarget: actionHandler];
}

/** Sets the target to which actions should be sent.

The target is not retained. */
- (void) setTarget: (id)aTarget
{
	SET_PROPERTY([NSValue valueWithNonretainedObject: aTarget], kETTargetProperty);
	[[self layout] syncLayoutViewWithItem: self];
}

/** Returns the target to which actions should be sent. */
- (id) target
{
	return [GET_PROPERTY(kETTargetProperty) nonretainedObjectValue];
}

/** Sets the action that can be sent by the action handler associated with 
the receiver.

This won't alter the action set on the receiver view, both are completely 
distinct. */
- (void) setAction: (SEL)aSelector
{
	/* NULL and nil are the same, so a NULL selector removes any existing entry */
	SET_PROPERTY(NSStringFromSelector(aSelector), kETActionProperty);
	[[self layout] syncLayoutViewWithItem: self];
}

/** Returns the action that can be sent by the action handler associated with 
the receiver. 

See also -setAction:. */
- (SEL) action
{
	NSString *selString = GET_PROPERTY(kETActionProperty);

	if (selString == nil)
		return NULL;

	return NSSelectorFromString(selString);
}

/** Updates the subject 'value' property when the widget view value changed.

See also -subject. */
- (void) didChangeViewValue: (id)newValue
{
	//ETLog(@"Did Change view value to %@", newValue);
	[self setValue: newValue forProperty: kETValueProperty];
}

/** Updates the view 'object value' property when the represented object value changed. */
- (void) didChangeRepresentedObjectValue: (id)newValue
{
	ETLog(@"Did Change represented object value to %@", newValue);
	[self syncView: [self view] withValue: newValue];
}

/* Editing */

/** Invokes -beginEditingForItem: on the action handler which makes the item view 
the first responder or the item when there is no view. */
- (void) beginEditing
{
	[[self actionHandler] beginEditingForItem: self];
}

/** Invokes -discardEditingForItem: on the action handler which in turn invokes 
-discardEditing on the item view when possible. */
- (void) discardEditing
{
	[[self actionHandler] discardEditingForItem: self];
}

/** Invokes -commitEditingForItem: on the action handler which in turn invokes 
-commitEditing on the item view when possible. */
- (BOOL) commitEditing
{
	return [[self actionHandler] commitEditingForItem: self];
}

/** Notifies the item it has begun to be edited.

This method is usually invoked by the item view or the action handler to allow  
the item to notify the base item controller about the editing.

You can invoke it in an action handler method when you want the possibility  
to react with -commitEditingForItem: or -discardEditingForItem: to an early 
editing termination by the controller.<br />

See also -objectDidEndEditing:. */
- (void) objectDidBeginEditing: (id)anEditor
{
	// NOTE: We implement NSEditorRegistration to allow the view which are 
	// bound to an item with -bind:toObject:XXX to notify the controller transparently.
	[[[self baseItem] controller] objectDidBeginEditing: anEditor];
}

/** Notifies the item the editing underway ended.

This method is usually invoked by the item view or the action handler to allow  
the item to notify the base item controller about the editing.

You must invoke it in an action handler method when you have previously call 
-objectDidBeginEditing and your editor has finished to edit a property.<br />

See also -objectDidBeginEditing:. */
- (void) objectDidEndEditing: (id)anEditor
{ 	
	[[[self baseItem] controller] objectDidEndEditing: anEditor];
}

/** Returns the custom inspector associated with the receiver. By default, 
returns nil.

-[NSObject(EtoileUI) inspect:] will show this inspector, unless nil is returned. */
- (id <ETInspector>) inspector
{
	id <ETInspector> inspector = GET_PROPERTY(kETInspectorProperty);
	[inspector setInspectedObjects: A(self)];
	return inspector;
}

/** Sets the custom inspector associated with the receiver. */
- (void) setInspector: (id <ETInspector>)inspector
{
	SET_PROPERTY(inspector, kETInspectorProperty);
}

/* Live Development */

/** This feature is not yet implemented. */
- (void) beginEditingUI
{
	id view = [self supervisorView];
	
	/* Notify to view */
	if (view != nil && [view respondsToSelector: @selector(beginEditingUI)])
		[view beginEditingUI];

	/* Notify decorator item chain */
	[[self decoratorItem] beginEditingUI];
}

@end
