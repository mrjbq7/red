Red [
	Title:   "Red runtime lexer"
	Author:  "Nenad Rakocevic"
	File: 	 %lexer.red
	Tabs:	 4
	Rights:  "Copyright (C) 2014-2015 Nenad Rakocevic. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

system/lexer: context [

	throw-error: function [spec [block!] /missing][
		src: back tail spec
		src/1: mold/flat/part get/any src/1 40
		if "^^/" = copy/part pos: skip tail src/1 -3 2 [remove/part pos 2]
		cause-error 'syntax any [all [missing 'missing] 'invalid] spec
	]

	make-binary: routine [
		start  [string!]
		end    [string!]
		base   [integer!]
		/local
			s	 [series!]
			p	 [byte-ptr!]
			len  [integer!]
			unit [integer!]
			ret  [red-binary!]
	][
		s:  GET_BUFFER(start)
		unit: GET_UNIT(s)
		p:	  string/rs-head start
		len:  end/head - start/head
		
		ret: as red-binary! stack/arguments
		ret/head: 0
		ret/header: TYPE_BINARY
		ret/node: switch base [
			16 [binary/decode-16 p len unit]
			2  [binary/decode-2  p len unit]
			64 [binary/decode-64 p len unit]
		]
		if ret/node = null [ret/header: TYPE_NONE]			;-- return NONE!
	]

	make-tuple: routine [
		start  [string!]
		end	   [string!]
		/local
			str  [series!]
			c	 [integer!]
			n	 [integer!]
			m	 [integer!]
			len  [integer!]
			unit [integer!]
			size [integer!]
			p	 [byte-ptr!]
			tp	 [byte-ptr!]
			ret  [red-value!]
	][
		str:  GET_BUFFER(start)
		unit: GET_UNIT(str)
		p:	  string/rs-head start
		len:  end/head - start/head
		ret: stack/arguments
		tp: (as byte-ptr! ret) + 4

		n: 0
		size: 0
		until [
			c: string/get-char p unit
			either c = as-integer #"." [
				size: size + 1
				tp/size: as byte! n
				n: 0
			][
				m: n * 10
				n: m
				m: n + c - #"0"
				n: m
			]
			p: p + unit
			len: len - 1
			zero? len
		]
		size: size + 1									;-- last number
		tp/size: as byte! n
		ret/header: TYPE_TUPLE or (size << 19)
		ret
	]

	make-number: routine [
		start  [string!]
		end	   [string!]
		type   [datatype!]
		/local
			str  [series!]
			c	 [integer!]
			n	 [integer!]
			m	 [integer!]
			len  [integer!]
			unit [integer!]
			p	 [byte-ptr!]
			neg? [logic!]
	][
		if type/value <> TYPE_INTEGER [
			make-float start end type					;-- decimal! escape path
			exit
		]
		str:  GET_BUFFER(start)
		unit: GET_UNIT(str)
		p:	  string/rs-head start
		len:  end/head - start/head
		neg?: no

		c: string/get-char p unit
		if any [
			c = as-integer #"+" 
			c = as-integer #"-"
		][
			neg?: c = as-integer #"-"
			p: p + unit
			len: len - 1
		]
		n: 0
		until [
			c: (string/get-char p unit) - #"0"
			if c >= 0 [									;-- skip #"'"
				m: n * 10
				if m < n [SET_RETURN(none-value) exit]	;-- return NONE on overflow
				n: m

				if all [n = 2147483640 c = 8][
					integer/box 80000000h				;-- special exit trap for -2147483648
					exit
				]

				m: n + c
				if m < n [SET_RETURN(none-value) exit]	;-- return NONE on overflow
				n: m
			]
			p: p + unit
			len: len - 1
			zero? len
		]
		integer/box either neg? [0 - n][n]
	]

	make-float: routine [
		start [string!]
		end	  [string!]
		type  [datatype!]
		/local
			str  [series!]
			cp	 [integer!]
			unit [integer!]
			len  [integer!]
			p	 [byte-ptr!]
			tail [byte-ptr!]
			cur	 [byte-ptr!]
			s0	 [byte-ptr!]
			byte [byte!]
			f	 [float!]
	][
		cur: as byte-ptr! "0000000000000000000000000000000"		;-- 32 bytes including NUL

		str:  GET_BUFFER(start)
		unit: GET_UNIT(str)
		p:	  string/rs-head start
		len:  end/head - start/head
		tail: p + (len << (unit >> 1))

		if len > 31 [cur: allocate len + 1]
		s0:   cur

		until [											;-- convert to ascii string
			cp: string/get-char p unit
			if cp <> as-integer #"'" [					;-- skip #"'"
				if cp = as-integer #"," [cp: as-integer #"."]
				cur/1: as-byte cp
				cur: cur + 1
			]
			p: p + unit
			p = tail
		]
		byte: cur/1										;-- store last byte
		cur/1: #"^@"									;-- replace the byte with null so to-float can use it as end of input
		f: string/to-float s0
		if len > 31 [free s0]
		either type/value = TYPE_FLOAT [float/box f][percent/box f / 100.0]
	]

	make-hexa: routine [
		start	[string!]
		end		[string!]
		return: [integer!]
		/local
			s	  [series!]
			unit  [integer!]
			p	  [byte-ptr!]
			head  [byte-ptr!]
			p4	  [int-ptr!]
			n	  [integer!]
			power [integer!]
			cp	  [byte!]
	][
		s: GET_BUFFER(start)
		unit: GET_UNIT(s)

		p: (string/rs-head end) - unit
		head: string/rs-head start

		n: 0
		power: 0
		while [p >= head][
			cp: switch unit [
				Latin1 [p/value]
				UCS-2  [as-byte ((as-integer p/2) << 8 + p/1)]
				UCS-4  [p4: as int-ptr! p as-byte p4/value]
			]
			if cp <> #"0" [
				case [
					all [#"0" <= cp cp <= #"9"][cp: cp - #"0"]
					all [#"A" <= cp cp <= #"F"][cp: cp - #"A" + 10]
					all [#"a" <= cp cp <= #"f"][cp: cp - #"a" + 10]
				]
				n: n + ((as-integer cp) << power)
			]
			power: power + 4
			p: p - unit
		]
		n
	]

	make-char: routine [
		start	[string!]
		end		[string!]
		/local
			n	  [integer!]
			value [red-value!]
	][
		n: make-hexa start end
		value: as red-value! integer/box n
		set-type value TYPE_CHAR
	]

	push-path: routine [
		stack [block!]
		type  [datatype!]
		/local
			path [red-path!]
	][
		path: as red-path! block/make-at as red-block! ALLOC_TAIL(stack) 4
		path/header: switch type/value [
			TYPE_GET_WORD [TYPE_GET_PATH]
			TYPE_LIT_WORD [TYPE_LIT_PATH]
			default [TYPE_PATH]
		]
		path/args: null
	]

	set-path: routine [
		stack [block!]
		/local
			path [red-path!]
	][
		path: as red-path! _series/pick as red-series! stack 1 null
		path/args: null
		set-type as red-value! path TYPE_SET_PATH
	]

	make-word: routine [
		src   [string!]
		type  [datatype!]
	][
		set-type
			as red-value! word/box (symbol/make-alt src) ;-- word/box puts it in stack/arguments
			type/value
	]

	to-word: func [
		stack [block!]
		src   [string!]
		type  [datatype!]
	][
		store stack make-word src type
	]

	pop: function [stack [block!]][
		value: last stack
		remove back tail stack

		either any [1 < length? stack head? stack/1][
			append/only last stack :value
		][
			pos: back tail stack						;-- root storage and offset-ed series (/into option)
			pos/1: insert/only last stack :value
		]
	]

	store: function [stack [block!] value][
		either any [1 < length? stack head? stack/1][
			append last stack value
		][
			pos: back tail stack						;-- root storage and offset-ed series (/into option)
			pos/1: insert last stack value
		]
	]

	transcode: function [
		src	[string!]
		dst	[block! none!]
		/part	
			length [integer! string!]
		return: [block!]
		/local
			new s e c hex pos value cnt type process path
			digit hexa-upper hexa-lower hexa hexa-char not-word-char not-word-1st
			not-file-char not-str-char not-mstr-char caret-char
			non-printable-char integer-end ws-ASCII ws-U+2k control-char
			four half non-zero path-end base base64-char slash-end not-url-char
	][
		cs:		[- - - - - - - - - - - - - - - - - - - - - - -]	;-- memoized bitsets
		stack:	clear []
		count?:	yes										;-- if TRUE, lines counter is enabled
		line: 	1

		append/only stack any [dst make block! 4]

		make-string: [
			new: make type (index? e) - index? s
			parse/case copy/part s e [					;@@ add /part option to parse!
				any [
					escaped-char (append new value)
					| #"^^"								;-- trash single caret chars
					| set c skip (append new c)
				]
			]
			new
		]

		make-file: [
			new: make type (index? e) - index? s
			append new dehex copy/part s e
			new
		]

		if cs/1 = '- [
			cs/1:  charset "0123465798"					;-- digit
			cs/2:  charset "ABCDEF"						;-- hexa-upper
			cs/3:  charset "abcdef"						;-- hexa-lower
			cs/4:  union cs/1 cs/2						;-- hexa
			cs/5:  union cs/4 cs/3						;-- hexa-char	
			cs/6:  charset {/\^^,[](){}"#%$@:;}			;-- not-word-char
			cs/7:  union union cs/6 cs/1 charset {'}	;-- not-word-1st
			cs/8:  charset {[](){}"@:;}					;-- not-file-char
			cs/9:  #"^""								;-- not-str-char
			cs/10: #"}"									;-- not-mstr-char
			cs/11: charset [#"^(40)" - #"^(5F)"]		;-- caret-char
			cs/12: charset [							;-- non-printable-char
				#"^(00)" - #"^(08)"						;-- (exclude TAB)
				#"^(0A)" - #"^(1F)"
			]
			cs/13: charset {^{"[]();xX}					;-- integer-end
			cs/14: charset " ^-^M"						;-- ws-ASCII, ASCII common whitespaces
			cs/15: charset [#"^(2000)" - #"^(200A)"]	;-- ws-U+2k, Unicode spaces in the U+2000-U+200A range
			cs/16: charset [ 							;-- Control characters
				#"^(00)" - #"^(1F)"						;-- C0 control codes
				#"^(80)" - #"^(9F)"						;-- C1 control codes
			]
			cs/17: charset "01234"						;-- four
			cs/18: charset "012345"						;-- half
			cs/19: charset "123456789"					;-- non-zero
			cs/20: charset {^{"[]();}					;-- path-end
			cs/21: union cs/1 charset [					;-- base64-char
				#"A" - #"Z" #"a" - #"z" #"+" #"/" #"="
			]
			cs/22: charset {[](){}":;}					;-- slash-end
			cs/23: charset {[](){}";}					;-- not-url-char
		]
		set [
			digit hexa-upper hexa-lower hexa hexa-char not-word-char not-word-1st
			not-file-char not-str-char not-mstr-char caret-char
			non-printable-char integer-end ws-ASCII ws-U+2k control-char
			four half non-zero path-end base64-char slash-end not-url-char
		] cs

		byte: [
			"25" half
			| "2" four digit
			| "1" digit digit
			| non-zero digit
			| digit
		]

		;-- Whitespaces list from: http://en.wikipedia.org/wiki/Whitespace_character
		ws: [
			pos: #"^/" (
				if count? [
					line: line + 1 
					;append/only lines to block! stack/tail?
				]
			)
			| ws-ASCII									;-- only the common whitespaces are matched
			| #"^(0085)"								;-- U+0085 (Newline)
			| #"^(00A0)"								;-- U+00A0 (No-break space)
			| #"^(1680)"								;-- U+1680 (Ogham space mark)
			| #"^(180E)"								;-- U+180E (Mongolian vowel separator)
			| ws-U+2k									;-- U+2000-U+200A range
			| #"^(2028)"								;-- U+2028 (Line separator)
			| #"^(2029)"								;-- U+2029 (Paragraph separator)
			| #"^(202F)"								;-- U+202F (Narrow no-break space)
			| #"^(205F)"								;-- U+205F (Medium mathematical space)
			| #"^(3000)"								;-- U+3000 (Ideographic space)
		]

		newline-char: [
			#"^/"
			| #"^(0085)"								;-- U+0085 (Newline)
			| #"^(2028)"								;-- U+2028 (Line separator)
			| #"^(2029)"								;-- U+2029 (Paragraph separator)
		]

		counted-newline: [pos: #"^/" (line: line + 1)]

		ws-no-count: [(count?: no) ws (count?: yes)]

		escaped-char: [
			"^^(" [
				[										;-- special case first
					"null" 	 (value: #"^(00)")
					| "back" (value: #"^(08)")
					| "tab"  (value: #"^(09)")
					| "line" (value: #"^(0A)")
					| "page" (value: #"^(0C)")
					| "esc"  (value: #"^(1B)")
					| "del"	 (value: #"^(7F)")
				]
				| pos: [2 6 hexa-char] e: (				;-- Unicode values allowed up to 10FFFFh
					value: make-char pos e
				)
			] #")"
			| #"^^" [
				[
					#"/" 	(value: #"^/")
					| #"-"	(value: #"^-")
					| #"?" 	(value: #"^(del)")			;@@FIXME
					| #"^^" (value: #"^^")				;-- caret escaping case
					| #"{"	(value: #"{")
					| #"}"	(value: #"}")
					| #"^""	(value: #"^"")
				]
				| pos: caret-char (value: pos/1 - 64)
			]
		]

		char-rule: [
			{#"} s: [
				 escaped-char
				| ahead [non-printable-char | not-str-char]
				  (throw-error [char! skip s -2])
				  reject
				| skip (value: s/1)
			][
				{"}
				| (throw-error [char! skip s -2])
			]
		]

		line-string: [
			{"} s: any [
				{^^"}
				| ahead [#"^"" | newline-char] break
				| escaped-char
				| skip
			]
			e: {"}
		]

		nested-curly-braces: [
			(cnt: 1)
			any [
				counted-newline 
				| "^^{"
				| "^^}"
				| #"{" (cnt: cnt + 1)
				| e: #"}" if (zero? cnt: cnt - 1) break
				| escaped-char
				| skip
			]
		]

		multiline-string: [
			#"{" s: nested-curly-braces (unless zero? cnt [throw-error [string! s]])
		]

		string-rule: [(type: string!) line-string | multiline-string]

		base-2-rule: [
			"2#{" s: any [counted-newline | 8 [#"0" | #"1" ] | ws-no-count | comment-rule] e: #"}"
			(base: 2)
		]

		base-16-rule: [
			"#{" s: any [counted-newline | 2 hexa-char | ws-no-count | comment-rule] e: #"}"
			(base: 16)
		]

		base-64-rule: [
			"64#{" s: any [counted-newline | base64-char | ws-no-count | comment-rule] e: #"}"			
			(base: 64)
		]

		binary-rule: [
			(type: binary!)
			base-16-rule | base-2-rule | base-64-rule
		]

		file-rule: [
			#"%" [
				line-string (process: make-string type: file!)
				| s: any [ahead [not-file-char | ws-no-count] break | skip] e:
				  (process: make-file type: file!)
			]
		]

		url-rule: [
			#":" not [not-url-char | ws-no-count | end]
			any [#"@" | #":" | ahead [not-file-char | ws-no-count] break | skip] e:
			(type: url! store stack do make-file)
		]

		symbol-rule: [
			some [ahead [not-word-char | ws-no-count | control-char] break | skip] e:
		]

		begin-symbol-rule: [							;-- 1st char in symbols is restricted
			[not ahead [not-word-1st | ws-no-count | control-char]]
			symbol-rule
		]

		path-rule: [
			ahead slash (								;-- path detection barrier
				push-path stack type					;-- create empty path
				to-word stack copy/part s e word!		;-- push 1st path element
				type: path!
			)
			some [
				slash
				s: [
					integer-number-rule			(store stack make-number s e type)
					| begin-symbol-rule			(to-word stack copy/part s e word!)
					| paren-rule
					| #":" s: begin-symbol-rule	(to-word stack copy/part s e get-word!)
					;@@ add more datatypes here
					| (throw-error [path! path])
					  reject
				]
			]
			opt [#":" (type: set-path! set-path back tail stack)][
				ahead [path-end | ws | end] | (throw-error [type path])
			]
			(pop stack)
		]
		
		special-words: [
			[
				#"%" [ws-no-count | end] (value: "%")	;-- special case for remainder op!
				| #"/" ahead [slash-end | slash | ws-no-count | control-char | end][
					#"/" 
					ahead [slash-end | ws-no-count | control-char | end] (value: "//")
					| (value: "/")
				]
			]
			opt [#":" (type: set-word!)]
			(to-word stack value type)				;-- special case for / and // as words
		]

		word-rule: 	[
			(type: word!) special-words
			| path: s: begin-symbol-rule (type: word!) [
				url-rule
				| path-rule							;-- path matched
				| opt [#":" (type: set-word!)]
				  (if type [to-word stack copy/part s e type])	;-- word or set-word matched
			]
		]

		get-word-rule: [
			#":" (type: get-word!) [
				special-words
				| s: begin-symbol-rule [
					path-rule (type: get-path!)
					| (to-word stack copy/part s e type)	;-- get-word matched
				]
			]
		]

		lit-word-rule: [
			#"'" (type: lit-word!) s: begin-symbol-rule [
				path-rule (type: lit-path!)				;-- path matched
				| (to-word stack copy/part s e type)	;-- lit-word matched
			] 
			opt [#":" (throw-error [type back s])]
		]

		issue-rule: [
			#"#" (type: issue!) s: symbol-rule (
				if (index? s) = index? e [throw-error [mold type skip s -4]]
				to-word stack copy/part s e type
			)
		]

		refinement-rule: [
			slash [
				some slash (type: word!) e:				;--  ///... case
				| ahead [not-word-char | ws-no-count | control-char] (type: word!) e: ;-- / case
				| symbol-rule (type: refinement! s: next s)
			]
			(to-word stack copy/part s e type)
		]
		
		sticky-word-rule: [								;-- protect from sticky words typos
			ahead [integer-end | ws-no-count | end | (throw-error [type s])]
		]
		hexa-rule: [2 8 hexa e: #"h"]

		tuple-value-rule: [
			byte 2 11 [dot byte] e: (type: tuple!)
		]

		tuple-rule: [tuple-value-rule sticky-word-rule]

		integer-number-rule: [
			opt [#"-" | #"+"] digit any [digit | #"'" digit] e: (type: integer!)
		]

		integer-rule: [
			float-special (value: make-number s e type)	;-- escape path for NaN, INFs
			| integer-number-rule
			  opt [float-number-rule | float-exp-rule e: (type: float!)]
			  opt [#"%" (type: percent!)]
			  sticky-word-rule
			  (value: make-number s e type)
			  opt [
				[#"x" | #"X"] s: integer-number-rule
				(value: as-pair value make-number s e type)
			  ]
		]

		float-special: [
			s: opt [#"-"] "1.#" [
				[[#"N" | #"n"] [#"a" | #"A"] [#"N" | #"n"]]
				| [[#"I" | #"i"] [#"N" | #"n"] [#"F" | #"f"]]
			] e: (type: float!)
		]

		float-exp-rule: [[#"e" | #"E"] opt [#"-" | #"+"] 1 3 digit]

		float-number-rule: [
			[dot | comma] digit any [digit | #"'" digit]
			opt float-exp-rule e: (type: float!)
		]

		float-rule: [
			opt [#"-" | #"+"] float-number-rule
			opt [#"%" (type: percent!)]
			sticky-word-rule
		]
		
		map-rule: [
			"#(" (append/only stack make block! 4)
			any-value
			#")" (
				value: back tail stack
				value/1: make map! value/1
				pop stack
			)
		]

		block-rule: [
			#"[" (append/only stack make block! 4)
			any-value
			#"]" (pop stack)
		]

		paren-rule: [
			#"(" (append/only stack make paren! 4)
			any-value 
			#")" (pop stack)
		]

		escaped-rule: [
			"#[" pos: any ws [
				  "true"  			(value: true)
				| "false" 			(value: false)
				| [
					"none!"			(value: none!)
					| "logic!"		(value: logic!)
					| "block!"		(value: block!)
					| "integer!"	(value: integer!)
					| "word!"		(value: word!)
					| "set-word!"	(value: set-word!)
					| "get-word!"	(value: get-word!)
					| "lit-word!"	(value: lit-word!)
					| "refinement!"	(value: refinement!)
					;| "binary!"	(value: binary!)
					| "string!"		(value: string!)
					| "char!"		(value: char!)
					| "bitset!"		(value: bitset!)
					| "path!"		(value: path!)
					| "set-path!"	(value: set-path!)
					| "lit-path!"	(value: lit-path!)
					| "get-path!"	(value: get-path!)
					| "native!"		(value: native!)
					| "action!"		(value: action!)
					| "op!"			(value: op!)
					| "issue!"		(value: issue!)
					| "paren!"		(value: paren!)
					| "function!"	(value: function!)
					| "routine!"	(value: routine!)
				]
				| "none" 			(value: none)
			] pos: any ws #"]"
		]

		comment-rule: [#";" [to lf | to end]]

		wrong-delimiters: [
			pos: [
				  #"]" (value: #"[") | #")" (value: #"(")
				| #"[" (value: #"]") | #"(" (value: #")")
			] :pos
			(throw-error/missing [value skip pos -3])
		]

		literal-value: [
			pos: (e: none) s: [
				comment-rule
				| escaped-rule		(store stack value)
				| tuple-rule		(store stack make-tuple s e)
				| hexa-rule			(store stack make-hexa s e)
				| binary-rule		if (value: make-binary s e base) (store stack value)
				| integer-rule		if (value) (store stack value)
				| float-rule		if (value: make-float s e type) (store stack value)
				| word-rule
				| lit-word-rule
				| get-word-rule
				| refinement-rule
				| file-rule			(store stack value: do process)
				| char-rule			(store stack value)
				| block-rule
				| paren-rule
				| string-rule		(store stack do make-string)
				| map-rule
				| issue-rule
			]
		]

		any-value: [pos: any [literal-value | ws]]

		red-rules: [any-value opt wrong-delimiters]

		unless either part [
			parse/case/part src red-rules length
		][
			parse/case src red-rules
		][
			throw-error ['value pos]
		]
		stack/1
	]
]
