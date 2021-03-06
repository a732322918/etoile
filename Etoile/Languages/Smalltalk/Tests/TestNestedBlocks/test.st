
NSObject subclass: SmalltalkTool [
	 run [
	     | numbers animals |
	     numbers := {'two'. 'three'. 'four'}.
	     animals := {'tigers'. 'ducks'}.
	     numbers do: [ :number |
	     	     animals do: [ :animal |
		     	     ETTranscript show: number.
		     	     ETTranscript show: ' '.
		     	     ETTranscript show: animal.
			     ETTranscript cr.
		     ]
	     ].
	 ]
]
