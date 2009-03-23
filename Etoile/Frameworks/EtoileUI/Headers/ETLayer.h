/*
	ETLayer.h
	
	Layer class models the traditional layer element, very common in Computer
	Graphics applications.
 
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
 
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <EtoileUI/ETLayoutItemGroup.h>

/** Each layer instance is basically a special node of the layout item tree. */

@interface ETLayer : ETLayoutItemGroup 
{
	//BOOL _visible;
	BOOL _outOfFlow;
}

- (void) setMovesOutOfLayoutFlow: (BOOL)floating;
- (BOOL) movesOutOfLayoutFlow;

/*- (void) setVisible;
- (BOOL) isVisible;*/

@end


@interface ETWindowLayer : ETLayer
{
	NSWindow *_rootWindow;
	NSMutableArray *_visibleWindows;
}

- (void) hideHardWindows;
- (void) showHardWindows;

@end

/** A window layout based on WM-based windows, or more precisely the windows 
as implemented by the widget backend (NSWindow in AppKit case). 

For now, only applies to the ETWindowLayer instance returned by 
+[ETLayoutItem windowGroup]. */
@interface ETWindowLayout : ETLayout
{

}

@end