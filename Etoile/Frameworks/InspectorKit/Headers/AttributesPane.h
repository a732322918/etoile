/*
   AttributesPane.h
   The attributes pane.

   Copyright (C) 2005 Saso Kiselkov
                 2007 Yen-Ju Chen

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

#import <PaneKit/PaneKit.h>
#import <InspectorKit/InspectorModule.h>
#import <InspectorKit/OSDateView.h>
#import <InspectorKit/PermissionsView.h>

@interface AttributesPane : PKPane <InspectorModule>
{
  NSPopUpButton *fileGroup;
  NSPopUpButton *fileOwner;
  NSTextField *fileSize;
  NSButton *computeSizeBtn;
  OSDateView *dateView;
  PermissionsView *permView;
  NSButton *okButton;
  NSButton *revertButton;

  NSDictionary *info;
  NSString *path;

  NSDictionary *users;
  NSDictionary *groups;
  NSDictionary *myGroups;
  NSString * user;
  NSString * group;
  BOOL modeChanged;
  unsigned oldMode;
  unsigned mode;
}

- (void) changePermissions: (id) sender;
- (void) changeOwner: (id) sender;
- (void) changeGroup: (id) sender;
- (void) computeSize: (id) sender;

@end
