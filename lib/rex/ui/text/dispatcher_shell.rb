# -*- coding: binary -*-
require 'rex/ui'
require 'pp'

module Rex
module Ui
module Text

###
#
# The dispatcher shell class is designed to provide a generic means
# of processing various shell commands that may be located in
# different modules or chunks of codes.  These chunks are referred
# to as command dispatchers.  The only requirement for command dispatchers is
# that they prefix every method that they wish to be mirrored as a command
# with the cmd_ prefix.
#
###
module DispatcherShell

	###
	#
	# Empty template base class for command dispatchers.
	#
	###
	module CommandDispatcher

		#
		# Initializes the command dispatcher mixin.
		#
		def initialize(shell)
			self.shell = shell
			self.tab_complete_items = []
		end

		#
		# Returns nil for an empty set of commands.
		#
		# This method should be overridden to return a Hash with command
		# names for keys and brief help text for values.
		#
		def commands
		end

		#
		# Returns an empty hash for an empty set of aliases.
		#
		# This method should be overridden to return a Hash with alias
		# names for keys and alias values as the hash values. e.g. { 'ses' => 'sessions -l'}
		#
		def aliases
			{}
		end

		#
		# Returns an empty set of commands.
		#
		# This method should be overridden if the dispatcher has commands that
		# should be treated as deprecated. Deprecated commands will not show up in
		# help and will not tab-complete, but will still be callable.
		#
		def deprecated_commands
			[]
		end

		#
		# Wraps shell.print_error
		#
		def print_error(msg = '')
			shell.print_error(msg)
		end

		#
		# Wraps shell.print_status
		#
		def print_status(msg = '')
			shell.print_status(msg)
		end

		#
		# Wraps shell.print_line
		#
		def print_line(msg = '')
			shell.print_line(msg)
		end

		#
		# Wraps shell.print_good
		#
		def print_good(msg = '')
			shell.print_good(msg)
		end

		#
		# Wraps shell.print
		#
		def print(msg = '')
			shell.print(msg)
		end

		#
		# Print a warning that the called command is deprecated and optionally
		# forward to the replacement +method+ (useful for when commands are
		# renamed).
		#
		def deprecated_cmd(method=nil, *args)
			cmd = caller[0].match(/`cmd_(.*)'/)[1]
			print_error "The #{cmd} command is DEPRECATED"
			if cmd == "db_autopwn"
				print_error "See http://r-7.co/xY65Zr instead"
			elsif method and self.respond_to?("cmd_#{method}")
				print_error "Use #{method} instead"
				self.send("cmd_#{method}", *args)
			end
		end

		def deprecated_help(method=nil)
			cmd = caller[0].match(/`cmd_(.*)_help'/)[1]
			print_error "The #{cmd} command is DEPRECATED"
			if cmd == "db_autopwn"
				print_error "See http://r-7.co/xY65Zr instead"
			elsif method and self.respond_to?("cmd_#{method}_help")
				print_error "Use 'help #{method}' instead"
				self.send("cmd_#{method}_help")
			end
		end

		#
		# Wraps shell.update_prompt
		#
		def update_prompt(prompt=nil, prompt_char = nil, mode = false)
			shell.update_prompt(prompt, prompt_char, mode)
		end

		def cmd_help_help
			print_line "There's only so much I can do"
		end

		#
		# Displays the help banner.  With no arguments, this is just a list of
		# all commands grouped by dispatcher.  Otherwise, tries to use a method
		# named cmd_#{+cmd+}_help for the first dispatcher that has a command
		# named +cmd+.  If no such method exists, uses +cmd+ as a regex to
		# compare against each enstacked dispatcher's name and dumps commands
		# of any that match.
		#
		def cmd_help(cmd=nil, *ignored)
			if cmd
				help_found = false
				cmd_found = false
				shell.dispatcher_stack.each do |dispatcher|
					next unless dispatcher.respond_to?(:commands)
					next if (dispatcher.commands.nil?)
					next if (dispatcher.commands.length == 0)

					if dispatcher.respond_to?("cmd_#{cmd}")
						cmd_found = true
						break unless dispatcher.respond_to? "cmd_#{cmd}_help"
						dispatcher.send("cmd_#{cmd}_help")
						help_found = true
						break
					end
				end

				unless cmd_found
					# We didn't find a cmd, try it as a dispatcher name
					shell.dispatcher_stack.each do |dispatcher|
						if dispatcher.name =~ /#{cmd}/i
							print_line(dispatcher.help_to_s)
							cmd_found = help_found = true
						end
					end
				end
				print_error("No help for #{cmd}, try -h") if cmd_found and not help_found
				print_error("No such command") if not cmd_found
			else
				print(shell.help_to_s)
			end
		end

		#
		# Tab completion for the help command
		#
		# By default just returns a list of all commands in all dispatchers.
		#
		def cmd_help_tabs(str, words)
			return [] if words.length > 1

			tabs = []
			shell.dispatcher_stack.each { |dispatcher|
				tabs += dispatcher.commands.keys
			}
			return tabs
		end

		alias cmd_? cmd_help

		#
		# Return a pretty, user-readable table of commands provided by this
		# dispatcher.
		#
		def help_to_s(opts={})
			# If this dispatcher has no commands, we can't do anything useful.
			return "" if commands.nil? or commands.length == 0

			# Display the commands
			tbl = Table.new(
				'Header'  => "#{self.name} Commands",
				'Indent'  => opts['Indent'] || 4,
				'Columns' =>
					[
						'Command',
						'Description'
					],
				'ColProps' =>
					{
						'Command' =>
							{
								'MaxWidth' => 12
							}
					})

			commands.sort.each { |c|
				tbl << c
			}

			return "\n" + tbl.to_s + "\n"
		end

		#
		# No tab completion items by default
		#
		attr_accessor :shell, :tab_complete_items

		#
		# Provide a generic tab completion for file names.
		#
		# If the only completion is a directory, this descends into that directory
		# and continues completions with filenames contained within.
		#
		def tab_complete_filenames(str, words)
			matches = ::Readline::FILENAME_COMPLETION_PROC.call(str)
			if matches and matches.length == 1 and File.directory?(matches[0])
				dir = matches[0]
				dir += File::SEPARATOR if dir[-1,1] != File::SEPARATOR
				matches = ::Readline::FILENAME_COMPLETION_PROC.call(dir)
			end
			matches
		end

	end # end CommandDispatcher module

	#
	# DispatcherShell derives from shell.
	#
	include Shell

	#
	# Initialize the dispatcher shell.
	#
	def initialize(prompt, prompt_char = '>', histfile = nil, framework = nil)
		super

		# Initialze the dispatcher array
		self.dispatcher_stack = []

		# Initialize the tab completion array
		self.tab_words = []
		self.on_command_proc = nil
	end

	#
	# This method accepts the entire line of text from the Readline
	# routine, stores all completed words, and passes the partial
	# word to the real tab completion function. This works around
	# a design problem in the Readline module and depends on the
	# Readline.basic_word_break_characters variable being set to \x00
	#
	def tab_complete(str)
		# Place the word list into an instance variable
		self.tab_words = get_words(str)

		# Pop the last word and pass it to the real method
		tab_complete_stub(self.tab_words.pop)
	end

	#
	# Performs tab completion of a command, if supported
	# Current words can be found in self.tab_words
	#
	def tab_complete_stub(str)
		items = []

		return nil if not str

		# puts "Words(#{tab_words.join(', ')}) Partial='#{str}'"

		# Next, try to match internal command/alias or value completion
		# Enumerate each entry in the dispatcher stack
		orig_tab_words = nil
		dispatcher_stack.each { |dispatcher|

			# TODO:  update this to use is_valid_dispatcher_command methods?
			# If no command is set and it supports commands, add them all and aliases
			# Or if the command is alias and aliases are supported, add all
			if ( (tab_words.empty? and dispatcher.respond_to?('commands')) or
				(tab_words[0] == "alias" and dispatcher.respond_to?("aliases")) )
				items.concat(dispatcher.commands.keys)
				items.concat(dispatcher.aliases.keys) if dispatcher.respond_to?("aliases")
			end


			if dispatcher.respond_to?("aliases")
				aleeus_value = dispatcher.aliases[tab_words[0]]
				if aleeus_value
					# then tab_words[0] is an alias, dup original for later use
					orig_tab_words = tab_words.dup
					tab_words.shift # drop the alias word
					# now insert aleeus_value into tab_words, however aleeus_value
					# might itself need to be broken down more.  e.g. if 's' is aliased to
					# 'sessions -l' we want to insert both 'sesssions' and '-l' as words
					# we use the same parsing scheme as the original, but don't check for trailing whitespace
					get_words(aleeus_value,false).each_with_index do |werd,idx|
						tab_words.insert(idx,werd)
						# e.g. if aleeus_value was 'sessions -l', then insert 
						# 'sessions' at 0 and insert '-l' at 1
						# this way we are tab completing the translated value, not the alias
					end
				end
			end

			# If the dispatcher exports a tab completion function, use it
			if (dispatcher.respond_to?('tab_complete_helper'))
				res = dispatcher.tab_complete_helper(str, tab_words)
			else
				res = tab_complete_helper(dispatcher, str, tab_words)
			end

			if (res.nil?)
				# A nil response indicates no optional arguments
				return [''] if items.empty?
			else
				# Otherwise we add the completion items to the list
				items.concat(res)
			end
		}

		# Verify that our search string is a valid regex
		begin
			Regexp.compile(str)
		rescue RegexpError
			str = Regexp.escape(str)
		end

		# XXX - This still doesn't fix some Regexp warnings:
		# ./lib/rex/ui/text/dispatcher_shell.rb:171: warning: regexp has `]' without escape

		# Match based on the partial word
		matches = items.find_all do |e|
			e =~ /^#{str}/
		# Prepend the rest of the command (or it gets replaced!)
		# using the original alias version if it was an alias
		end

		# if orig_tab_words is not nil, this was an alias situation, so we use those words, assuming
		# AliasTranslateOnTab is not something true-like (the datastore always returns a String)
		if ( orig_tab_words and not framework.datastore['AliasTranslateOnTab'] =~ /^(y|t|1)/i)
			# datastore['AliasTranslateOnTab'] can be used to toggle this behavior
			# sometimes you'd like your alias to get translated to it's real command when you tab (set it to true)
			# and sometimes you'd prefer that the alias remained as is while tab completing (set to false, default)
			matches.map do |e|
				orig_tab_words.dup.push(e).join(' ')
			end
		else
			matches.map do |e|
				tab_words.dup.push(e).join(' ')
			end
		end
	end

	#
	# Provide command-specific tab completion
	#
	def tab_complete_helper(dispatcher, str, words)
		items = []

		tabs_meth = "cmd_#{words[0]}_tabs"
		# Is the user trying to tab complete one of our commands?
		if ( is_valid_dispatcher_command?(words[0],dispatcher,false) and dispatcher.respond_to?(tabs_meth) )
			res = dispatcher.send(tabs_meth, str, words)
			return [] if res.nil?
			items.concat(res)
		else
			# Avoid the default completion list for known commands
			return []
		end
		return items
	end

	#
	# determine if a given method (command) is valid
	#
	def is_valid_dispatcher_command?(method,specific_dispatcher=nil,include_deprecated=false)
		if specific_dispatcher
			dispatchers = [specific_dispatcher]
		else
			dispatchers = dispatcher_stack
		end
		dispatchers.each do |dispatcher|
			next if not dispatcher.respond_to?('commands')
			if include_deprecated
				if (dispatcher.commands.has_key?(method) or dispatcher.deprecated_commands.include?(method))
					return true
				end
			elsif dispatcher.commands.has_key?(method)
				return true
			end
		end
		return false
	end

	#
	# find all dispatchers that respond to the given method (command) if any
	#
	def get_responding_dispatchers(method,include_deprecated=true)
		resp_dispatchers = []
		dispatcher_stack.each do |dispatcher|
			next if not dispatcher.respond_to?('commands') # don't bother if it doesn't have any commands
			resp_dispatchers << dispatcher if is_valid_dispatcher_command?(method,dispatcher,include_deprecated)
		end
		# otherwise, we didn't find a winner
		return resp_dispatchers
	end

	#
	# Run a single command line.
	#
	def run_single(line)
		arguments = parse_line(line)
		method    = arguments.shift
		found     = false
		error     = false

		# If output is disabled output will be nil
		output.reset_color if (output)

		if (method)
			entries = dispatcher_stack.length
			# to avoid walking the dispatcher stack twice, and we need the responding dispatchers,
			# we don't use is_valid_command? but rather get_responding_dispatchers
			dispatchers = get_responding_dispatchers(method)
			if (dispatchers and not dispatchers.empty?)
				dispatchers.each do |dispatcher|
					begin
						self.on_command_proc.call(line.strip) if self.on_command_proc
						run_command(dispatcher, method, arguments)
						found = true
					rescue
						error = $!
						print_error(
							"Error while running command #{method}: #{$!}" +
							"\n\nCall stack:\n#{$@.join("\n")}")
					rescue ::Exception
						error = $!
						print_error(
							"Error while running command #{method}: #{$!}")
					end

					# If the dispatcher stack changed as a result of this command,
					# break out
					break if (dispatcher_stack.length != entries)
				end
			end

			if (found == false and error == false)
				unknown_command(method, line)
			end
		end

		return found
	end
	#
	# Runs the supplied command on the given dispatcher.
	#
	def run_command(dispatcher, method, arguments)
		self.busy = true

		if(blocked_command?(method))
			print_error("The #{method} command has been disabled.")
		else
			dispatcher.send('cmd_' + method, *arguments)
		end
		self.busy = false
	end

	#
	# If the command is unknown...
	#
	def unknown_command(method, line)
		print_error("Unknown command: #{method}.")
	end

	#
	# Push a dispatcher to the front of the stack.
	#
	def enstack_dispatcher(dispatcher)
		self.dispatcher_stack.unshift(inst = dispatcher.new(self))

		inst
	end

	#
	# Pop a dispatcher from the front of the stacker.
	#
	def destack_dispatcher
		self.dispatcher_stack.shift
	end

	#
	# Adds the supplied dispatcher to the end of the dispatcher stack so that
	# it doesn't affect any enstack'd dispatchers.
	#
	def append_dispatcher(dispatcher)
		inst = dispatcher.new(self)
		self.dispatcher_stack.each { |disp|
			if (disp.name == inst.name)
				raise RuntimeError.new("Attempting to load already loaded dispatcher #{disp.name}")
			end
		}
		self.dispatcher_stack.push(inst)

		inst
	end

	#
	# Removes the supplied dispatcher instance.
	#
	def remove_dispatcher(name)
		self.dispatcher_stack.delete_if { |inst|
			(inst.name == name)
		}
	end

	#
	# Returns the current active dispatcher
	#
	def current_dispatcher
		self.dispatcher_stack[0]
	end

	#
	# Return a readable version of a help banner for all of the enstacked
	# dispatchers.
	#
	# See +CommandDispatcher#help_to_s+
	#
	def help_to_s(opts = {})
		str = ''

		dispatcher_stack.reverse.each { |dispatcher|
			str << dispatcher.help_to_s
		}

		return str
	end


	#
	# Returns nil for an empty set of blocked commands.
	#
	def blocked_command?(cmd)
		return false if not self.blocked
		self.blocked.has_key?(cmd)
	end

	#
	# Block a specific command
	#
	def block_command(cmd)
		self.blocked ||= {}
		self.blocked[cmd] = true
	end

	#
	# Unblock a specific command
	#
	def unblock_command(cmd)
		self.blocked || return
		self.blocked.delete(cmd)
	end


	attr_accessor :dispatcher_stack # :nodoc:
	attr_accessor :tab_words # :nodoc:
	attr_accessor :busy # :nodoc:
	attr_accessor :blocked # :nodoc:

	protected
	def get_words(str, check_trail_ws=true)
		if check_trail_ws
			# Check trailing whitespace so we can tell 'x' from 'x '
			str_match = str.match(/\s+$/)
			str_trail = (str_match.nil?) ? '' : str_match[0]
		end

		# Split the line up by whitespace into words
		str_words = str.split(/[\s\t\n]+/)

		# Append an empty word if we are checking for trailing whitespace & we had some
		str_words << '' if (check_trail_ws and str_trail.length > 0)
		return str_words
	end

end

end
end
end
