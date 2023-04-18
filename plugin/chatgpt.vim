
" ChatGPT Vim Plugin
"
" Ensure Python3 is available
if !has('python3')
  echo "Python 3 support is required for ChatGPT plugin"
  finish
endif

" Add ChatGPT dependencies
python3 << EOF
import sys
try:
    import openai
except ImportError:
    print("Error: openai module not found. Install with pip.")
    raise
import vim
import os

try:
    vim.eval('g:chat_gpt_max_tokens')
except:
    vim.command('let g:chat_gpt_max_tokens=2000')
EOF

" Set API key
python3 << EOF
openai.api_key = os.getenv('CHAT_GPT_KEY') or vim.eval('g:chat_gpt_key')
EOF

" Function to show ChatGPT responses in a new buffer (improved)
function! DisplayChatGPTResponse(response, ...)
  if a:response == ''
    return
  endif

  let original_syntax = &syntax

  let bufnr = bufnr('ChatGPTResponse')
  if bufnr == -1
    new ChatGPTResponse
  else
    if bufwinnr(bufnr) != -1
      execute bufwinnr(bufnr) . 'wincmd w'
    else
      execute 'sbuffer' bufnr
    endif
  endif

  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  setlocal modifiable
  execute 'setlocal syntax='. original_syntax

  if a:0 == 0 " 没有额外参数表示追加内容
    silent! normal! gg"_dG
    call setline(1, split(a:response, '\n'))
  else
    let last_line = line('$')
    call append(last_line, split(a:response, '\n'))
    silent! normal! G
  endif

  setlocal nomodifiable
  wincmd p
endfunction

function! AskChatGPT(prompt)
  call ChatGPT(a:prompt)
  call DisplayChatGPTResponse(g:result, 'append')
endfunction

" Function to interact with ChatGPT
function! ChatGPT(prompt) abort
  python3 << EOF
def chat_gpt(prompt):
  max_tokens = int(vim.eval('g:chat_gpt_max_tokens'))

  try:
    response = openai.ChatCompletion.create(
      model="gpt-3.5-turbo",
      messages=[{"role": "user", "content": prompt}],
      max_tokens=max_tokens,
      stop=None,
      temperature=0.7,
      request_timeout=10
    )
    result = response.choices[0].message.content.strip()
    vim.command("let g:result = '{}'".format(result.replace("'", "''")))
  except Exception as e:
    print("Error:", str(e))
    vim.command("let g:result = ''")

chat_gpt(vim.eval('a:prompt'))
EOF
endfunction

function! ChatGPTTranslate(prompt) abort
  python3 << EOF
def chat_gpt(prompt):
  max_tokens = int(vim.eval('g:chat_gpt_max_tokens'))
  try:
    response = openai.ChatCompletion.create(
      model="gpt-3.5-turbo",
      messages=[
        {"role": "system", "content": "You are a translation engine that can only translate text and cannot interpret it."},
        {"role": "user", "content": "translate from english to chinese"},
        {"role": "user", "content": prompt.strip()},
      ],
      max_tokens=max_tokens,
      stop=None,
      temperature=0.7,
      request_timeout=16
    )
    result = response.choices[0].message.content.strip()
    vim.command("let g:result = '{}'".format(result.replace("'", "''")))
  except Exception as e:
    print("Error:", str(e))
    vim.command("let g:result = ''")

chat_gpt(vim.eval('a:prompt'))
EOF
endfunction

function! SendHighlightedCodeToChatGPT(ask, line1, line2, context)
  " Save the current yank register
  let save_reg = @@
  let save_regtype = getregtype('@')

  " Yank the lines between line1 and line2 into the unnamed register
  execute 'normal! ' . a:line1 . 'GV' . a:line2 . 'Gy'

  " Send the yanked text to ChatGPT
  let yanked_text = @@

  if a:ask == 'translate'
    call ChatGPTTranslate(yanked_text)
  else
    let prompt = 'Do you like my code?\n' . yanked_text
    if a:ask == 'rewrite'
      let prompt = 'I have the following code snippet, can you rewrite it more idiomatically?\n' . yanked_text
      if len(a:context) > 0
        let prompt = 'I have the following code snippet, can you rewrite to' . a:context . '?\n' . yanked_text
      endif
    elseif a:ask == 'review'
      let prompt = 'I have the following code snippet, can you provide a code review for?\n' . yanked_text
    elseif a:ask == 'explain'
      let prompt = 'I have the following code snippet, can you explain it?\n' . yanked_text
      if len(a:context) > 0
        let prompt = 'I have the following code snippet, can you explain, ' . a:context . '?\n' . yanked_text
      endif
    elseif a:ask == 'test'
      let prompt = 'I have the following code snippet, can you write a test for it?\n' . yanked_text
      if len(a:context) > 0
        let prompt = 'I have the following code snippet, can you write a test for it, ' . a:context . '?\n' . yanked_text
      endif
    elseif a:ask == 'fix'
      let prompt = 'I have the following code snippet, it has an error I need you to fix:\n' . yanked_text
      if len(a:context) > 0
        let prompt = 'I have the following code snippet I would want you to fix, ' . a:context . ':\n' . yanked_text
      endif
    endif
    call ChatGPT(prompt)
  endif


  call DisplayChatGPTResponse(g:result)
  " Restore the original yank register
  let @@ = save_reg
  call setreg('@', save_reg, save_regtype)
endfunction

function! GenerateCommitMessage()
  " Save the current position and yank register
  let save_cursor = getcurpos()
  let save_reg = @@
  let save_regtype = getregtype('@')

  " Yank the entire buffer into the unnamed register
  normal! ggVGy

  " Send the yanked text to ChatGPT
  let yanked_text = @@
  let prompt = 'I have the following code changes, can you write a helpful commit message, including a short title?\n' . yanked_text
  call ChatGPT(prompt)

  " Save the current buffer
  silent! write

  " Insert the response into the new buffer
  call setline(1, split(g:result, '\n'))
  setlocal modifiable

  " Go back to the original buffer
  wincmd p

  " Restore the original yank register and position
  let @@ = save_reg
  call setreg('@', save_reg, save_regtype)
  call setpos('.', save_cursor)
endfunction
"
" Commands to interact with ChatGPT
command! -nargs=1 Ask call AskChatGPT(<q-args>)
command! -range  -nargs=? Explain call SendHighlightedCodeToChatGPT('explain', <line1>, <line2>, <q-args>)
command! -range Translate call SendHighlightedCodeToChatGPT('translate', <line1>, <line2>, '')
command! -range Review call SendHighlightedCodeToChatGPT('review', <line1>, <line2>, '')
command! -range -nargs=? Rewrite call SendHighlightedCodeToChatGPT('rewrite', <line1>, <line2>, <q-args>)
command! -range -nargs=? Test call SendHighlightedCodeToChatGPT('test', <line1>, <line2>, <q-args>)
command! -range -nargs=? Fix call SendHighlightedCodeToChatGPT('fix', <line1>, <line2>, <q-args>)
command! GenerateCommit call GenerateCommitMessage()
