" ABB Rapid Command indent file for Vim
" Language: ABB Rapid Command
" Maintainer: Patrick Meiser-Knosowski <knosowski@graeff.de>
" Version: 2.2.2
" Last Change: 09. Jul 2020
" Credits: Based on indent/vim.vim
"
" Suggestions of improvement are very welcome. Please email me!
"
" Known bugs: ../doc/rapid.txt
"
" TODO
" * indent wrapped lines which do not end with an ; or special key word,
"     maybe this is a better idea, but then () and [] has to be changed as
"     well
"

if exists("g:rapidNoSpaceIndent")
  if !exists("g:rapidSpaceIndent")
    let g:rapidSpaceIndent = !g:rapidNoSpaceIndent
  endif
  unlet g:rapidNoSpaceIndent
endif

" Only load this indent file when no other was loaded.
if exists("b:did_indent") || exists("g:rapidNoIndent") && g:rapidNoIndent==1
  finish
endif
let b:did_indent = 1

setlocal nolisp
setlocal nosmartindent
setlocal autoindent
setlocal indentexpr=GetRapidIndent()
setlocal indentkeys=!^F,o,O,0=~endmodule,0=~error,0=~undo,0=~backward,0=~endproc,0=~endrecord,0=~endtrap,0=~endfunc,0=~else,0=~endif,0=~endtest,0=~endfor,0=~endwhile,:
let b:undo_indent="setlocal lisp< si< ai< inde< indk<"

if get(g:,'rapidSpaceIndent',1)
  " use spaces for indention, 2 is enough, more or even tabs are looking awful
  " on the teach pendant
  setlocal softtabstop=2
  setlocal shiftwidth=2
  setlocal expandtab
  setlocal shiftround
  let b:undo_indent = b:undo_indent." sts< sw< et< sr<"
endif

" Only define the function once.
if exists("*GetRapidIndent")
  finish
endif

let s:keepcpo= &cpo
set cpo&vim

function GetRapidIndent()
  let ignorecase_save = &ignorecase
  try
    let &ignorecase = 0
    return s:GetRapidIndentIntern()
  finally
    let &ignorecase = ignorecase_save
  endtry
endfunction

function s:GetRapidIndentIntern() abort
  let l:currentLine = getline(v:lnum)
  if  l:currentLine =~ '^!' && !get(g:,'rapidCommentIndent',0)
    " if first char is ! line comment, do not change indent
    " this may be usefull if code did get commented out at the first column
    return 0
  endif
  " Find a non-blank line above the current line.
  let l:preNoneBlankLineNum = s:RapidPreNoneBlank(v:lnum - 1)
  if  l:preNoneBlankLineNum == 0
    " At the start of the file use zero indent.
    return 0
  endif
  let l:preNoneBlankLine = getline(l:preNoneBlankLineNum)
  let l:ind = indent(l:preNoneBlankLineNum)

  " Add a 'shiftwidth'
  let l:i = match(l:preNoneBlankLine, '\c\v^\s*
          \(
            \((local|task|global)\s+)?
            \(module\s+\w
              \|record\s+\w
              \|proc\s+\w
              \|func\s+\w
              \|trap\s+\w
            \)
          \|[^!]*<then>\s*(!.*)?$
          \|else>
          \|[^!]*<do>\s*(!.*)?$
          \|case>[^!]+:
          \|default>\s*:
          \)'
        \)
  if l:i >= 0
    let l:ind += &sw
  endif
  let l:i = match(l:preNoneBlankLine, '\c\v^\s*(backward|error|undo)>')
  if l:i >= 0
    let l:ind += &sw
  endif

  " Subtract a 'shiftwidth'
  if l:currentLine =~ '\c\v^\s*
        \(
            \end(module|record|proc|func|trap)>
            \|end(if|for|while|test)>
            \|else>
            \|elseif>
            \|case>[^!]+:
            \|default>\s*:
        \)'
    let l:ind -= &sw
  endif
  if l:currentLine =~ '\c\v^\s*(backward|error|undo)>'
    let l:ind -= &sw
  endif

  " first case after a test
  if l:currentLine =~ '\c\v^\s*case>' && l:preNoneBlankLine =~ '\c\v^\s*test>'
    let l:ind += &sw
  endif

  " continued lines with () or []
  let l:OpenSum  = s:RapidLoneParen(l:preNoneBlankLineNum,"(") + s:RapidLoneParen(l:preNoneBlankLineNum,"[")
  let l:CloseSum = s:RapidLoneParen(l:preNoneBlankLineNum,")") + s:RapidLoneParen(l:preNoneBlankLineNum,"]")
  if l:OpenSum > l:CloseSum
    let l:ind += (l:OpenSum * 4 * &sw)
  elseif l:OpenSum < l:CloseSum
    let l:ind -= (l:CloseSum * 4 * &sw)
  endif

  return l:ind
endfunction

" Returns the length of the line until a:str occur outside a string or
" comment. Search starts at a:start
" Note: rapidTodoComment and rapidDebugComment are not taken into account
function s:RapidLenTilStr(lnum,str,start) abort
  let s:line = getline(a:lnum)

  let s:len = strlen(s:line)
  " if s:len >= 4096
  "   return 4096 " line too long; ignored
  " endif

  let s:i = a:start
  while s:i < s:len
    let s:i = stridx(s:line, a:str, s:i)
    if s:i < 0
      " a:str not found, return full length
      return s:len
    elseif     synIDattr(synID(a:lnum,s:i+1,0),"name") != "rapidString"
          \&&  synIDattr(synID(a:lnum,s:i+1,0),"name") != "rapidConcealableString"
          \&& (synIDattr(synID(a:lnum,s:i+1,0),"name") != "rapidComment" || a:str =~ '^!')
      " a:str found outside string or line comment
      return s:i
    endif
    " a:str is part of string or line comment
    let s:i += 1 " continue search for a:str
  endwhile

  " a:str not found or a:start>=s:len, return full length
  return s:len
endfunction

" a:lchar shoud be one of (, ), [, ], { or }
" returns the number of opening/closing parenthesise which have no
" closing/opening match in getline(a:lnum)
function s:RapidLoneParen(lnum,lchar) abort
  if a:lchar == "(" || a:lchar == ")"
    let s:opnParChar = "("
    let s:clsParChar = ")"
  elseif a:lchar == "[" || a:lchar == "]"
    let s:opnParChar = "["
    let s:clsParChar = "]"
  elseif a:lchar == "{" || a:lchar == "}"
    let s:opnParChar = "{"
    let s:clsParChar = "}"
  else
    return 0
  endif

  let s:line = getline(a:lnum)

  " look for the first ! which is not part of a string 
  let s:len = s:RapidLenTilStr(a:lnum,"!",0)
  if s:len == 0
    return 0 " first char is !; ignored
  endif
  " if s:len >= 4096
  "   return 0 " line too long; ignored
  " endif

  let s:opnParen = 0
  " count opening brakets
  let s:i = 0
  while s:i < s:len
    let s:i = stridx(s:line, s:opnParChar, s:i)
    if s:i >= 0 && s:i <= s:len
      " brakets that are part of a strings or comment are ignored
      if        synIDattr(synID(a:lnum,s:i+1,0),"name") != "rapidString"
            \&& synIDattr(synID(a:lnum,s:i+1,0),"name") != "rapidConcealableString"
            \&& synIDattr(synID(a:lnum,s:i+1,0),"name") != "rapidComment"
        let s:opnParen += 1
      endif
    else
      let s:i = s:len
    endif
    let s:i += 1
  endwhile

  let s:clsParen = 0
  " count closing brakets
  let s:i = 0
  while s:i < s:len
    let s:i = stridx(s:line, s:clsParChar, s:i)
    if s:i >= 0 && s:i <= s:len
      " brakets that are part of a strings or comment are ignored
      if        synIDattr(synID(a:lnum,s:i+1,0),"name") != "rapidString"
            \&& synIDattr(synID(a:lnum,s:i+1,0),"name") != "rapidConcealableString"
            \&& synIDattr(synID(a:lnum,s:i+1,0),"name") != "rapidComment"
        let s:clsParen += 1
      endif
    else
      let s:i = s:len
    endif
    let s:i += 1
  endwhile

  if (a:lchar == "(" || a:lchar == "[" || a:lchar == "{") && s:opnParen>s:clsParen
    return (s:opnParen-s:clsParen)
  elseif (a:lchar == ")" || a:lchar == "]" || a:lchar == "}") && s:clsParen>s:opnParen
    return (s:clsParen-s:opnParen)
  endif

  return 0
endfunction

" This function works almost like prevnonblank() but handles %%%-headers and
" comments like blank lines
function s:RapidPreNoneBlank(lnum) abort
  let nPreNoneBlank = prevnonblank(a:lnum)
  " At the start of the file use zero indent.
  if nPreNoneBlank == 0
    return 0
  endif

  let l:i=1
  while l:i>=1 && nPreNoneBlank>=0
    if getline(nPreNoneBlank) =~ '\v\c^\s*
          \(\%\%\%.*$
          \|(!.*)?$
          \)'
      let nPreNoneBlank = prevnonblank(nPreNoneBlank - 1)
      " At the start of the file use zero indent.
      if nPreNoneBlank == 0
        return 0
      endif
    else
      let l:i=0
    endif
  endwhile

  return nPreNoneBlank
endfunction

let &cpo = s:keepcpo
unlet s:keepcpo

" vim:sw=2 sts=2 et
