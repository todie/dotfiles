" -- Plugins ===================
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
        \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif
" ==============================
call plug#begin('~/.vim/plugged')
" ------------------------------
" - basic ------
Plug 'tpope/vim-fugitive'   " git
Plug 'tpope/vim-commentary' " comments
Plug 'tpope/vim-surround'   " braces,parens,quotes
" - panels -----
Plug 'christoomey/vim-tmux-navigator' " seamless tmux+vim navigation
Plug 'airblade/vim-gitgutter'
Plug 'scrooloose/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'   " nerdtree git icons
Plug 'majutsushi/tagbar'
Plug 'jlanzarotta/bufexplorer'
" - enhance ----
Plug 'editorconfig/editorconfig-vim' " enforce editor configs
Plug 'ervandew/supertab'             " tab do all the things
Plug 'godlygeek/tabular'             " god mode table alignment
Plug 'mileszs/ack.vim'               " better grepping ( source code aware )
Plug 'ctrlpvim/ctrlp.vim'            " fuzzy file finder
" - develop ----
Plug 'ludovicchabant/vim-gutentags'
Plug 'MarcWeber/vim-addon-mw-utils'
Plug 'tomtom/tlib_vim'
Plug 'garbas/vim-snipmate'
Plug 'honza/vim-snippets'
" - filetypes ----
Plug 'plasticboy/vim-markdown' " Markdown support
Plug 'leafgarland/typescript-vim' " typescript support
Plug 'avakhov/vim-yaml'        " yaml syntax support
Plug 'chrisbra/vim-zsh'

" ------------------------------
call plug#end()
" ==============================
" Basic
set autoread                            " relead on external file changes
set backspace=indent,eol,start          " backspace behavior
set clipboard=unnamed,unnamedplus       " enable clipboard
set encoding=utf-8                      " enable utf-8 support
set hidden                              " hide buffers, don't close
set number                              " show line numbers
set wildmenu wildmode=longest:full,full " wildmenu settings
set wildcharm=<Tab>                     " wildmenu character
set showcmd                             " show command keys
set splitbelow splitright

" UI
if exists('+termguicolors')
  " enable truecolor in tmux
  set termguicolors
  set background=dark
endif

set sidescroll=6
set listchars=eol:¶,trail:•,tab:▸\               " whitespace characters
set showbreak=¬\                                 " Wrapping character
set showmatch

" Tabs & Indentation
set tabstop=2 softtabstop=2 shiftwidth=2

" Search
set hlsearch ignorecase incsearch smartcase      " search options

" Undo & Backup
set nobackup noswapfile nowritebackup            " disable backup and swap files
set undofile undodir=~/.vim/undo undolevels=9999 " undo options

" Performance Tuning
set lazyredraw   " enable lazy redraw
set nocursorline " disable cursorline
set noshowmode
set ttyfast      " enable fast terminal connection

" Tags
set tags+=tags
set tags+=../tags
set tags+=~/.tags
set tags+=~/.local/share/tags

" -- Key Binds =========================================
let mapleader=','
nnoremap <leader>r :source $MYVIMRC<CR>|         "reload .vimrc
nnoremap <leader>, :let @/=''<CR>:noh<CR>|       " clear search
nnoremap <leader>w :set wrap! wrap?<CR>|         " toggle wrapping
nnoremap <leader>l :set list! list?<CR>|         " show invisible character
nnoremap <leader>m :marks<CR>|                   " list marks
nnoremap <leader>p :set invpaste paste?<CR>|     " toggle paste mode
nnoremap <leader>- :split<CR>|                   " split horizontal
nnoremap <leader>\ :vsplit<CR>|                  " split vertical
cnoreabbrev w!! w !sudo tee > /dev/null %|       " write file with sudo
" -- buffers ----
nnoremap <leader>o :edit<space><Tab>|            " open buffer
nnoremap <leader>x :bd<CR>|                      " close buffer
nnoremap <leader>b :ls<CR>:buffer<space>|        " show buffer
nnoremap <silent> <leader>n :enew<CR>|           " new empty buffer
" -- text ----
map <leader>d "_d|                               " delete selected text
nnoremap <silent> <leader>i gg=G``<CR>|          " indent file
nnoremap <silent> <leader># :g/\v^(#\|$)/d_<CR>| " delete commented blank lines
nnoremap <leader>s :retab<CR>|                   " convert tabs to space
nnoremap <silent> <leader>t :%s/.\+$//e<CR>|     " trim whitespace            
" -- quick edit ----
nnoremap <leader>ed :edit ~/.dotfiles/<CR>|
nnoremap <leader>ev :edit ~/.vimrc<CR>|
nnoremap <leader>et :edit ~/.tmux.conf<CR>|
nnoremap <leader>eg :edit ~/.gitconfig<CR>|
" -- function keys ----
" <F1> help
nnoremap <F2> :NERDTreeToggle<CR>
" <F3> Ctrl-P Plugin
nnoremap <F4> gg=G''
nnoremap <F5> :make!<cr>
nnoremap <F6> :<C-U>setlocal lcs=tab:>-,trail:-,eol:$ list! list? <CR>
nnoremap <F8> :TagbarToggle<CR>

" == Nerd Tree ==
" -- start up
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists("s:std_in") | exe 'NERDTree' argv()[0] | wincmd p | ene | exe 'cd '.argv()[0] | endif
" -- shut down
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif
" == fugitive ==
nnoremap <leader>gs :Gstatus<CR>
" == Ack ==
if executable('ag')
  let g:ackprg = 'ag --vimgrep' " use ag instead of default
endif
" == Ctrl-P ==
let g:ctrlp_map = '<F3>'
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_working_path_mode = 'ra'
set wildignore+=*/tmp/*,*.so,*.swp,*.zip     " MacOSX/Linux
"set wildignore+=*\\tmp\\*,*.swp,*.zip,*.exe  " Windows
let g:ctrlp_custom_ignore = {
      \ 'dir':  '\v[\/]\.(git|hg|svn)$',
      \ 'file': '\v\.(exe|so|dll)$',
      \ 'link': 'some_bad_symbolic_links',
      \ }

