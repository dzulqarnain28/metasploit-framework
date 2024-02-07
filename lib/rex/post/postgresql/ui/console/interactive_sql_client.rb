# -*- coding: binary -*-
module Rex
module Post
module PostgreSQL
module Ui

###
#
# Mixin that is meant to extend a sql client class in a
# manner that adds interactive capabilities.
#
###
module Console::InteractiveSqlClient

  include Rex::Ui::Interactive

  #
  # Interacts with self.
  #
  def _interact
    while self.interacting
      sql_input = _multiline_with_fallback
      self.interacting = (sql_input[:status] != :exit)
      # We need to check that the user is still interacting, i.e. if ctrl+z is triggered when requesting user input
      break unless (self.interacting && sql_input[:result])

      self.on_command_proc.call(sql_input[:result].strip) if self.on_command_proc

      formatted_query = client_dispatcher.process_query(query: sql_input[:result])
      print_status "Executing query: #{formatted_query}"
      client_dispatcher.cmd_query(formatted_query)
    end
  end

  #
  # Called when an interrupt is sent.
  #
  def _interrupt
    prompt_yesno('Terminate interactive SQL prompt?')
  end

  #
  # Suspends interaction with the interactive REPL interpreter
  #
  def _suspend
    if (prompt_yesno('Background interactive SQL prompt?') == true)
      self.interacting = false
    end
  end

  #
  # We don't need to do any clean-up when finishing the interaction with the REPL
  #
  def _interact_complete
    # noop
  end

  def _winch
    # noop
  end

  # Try getting multi-line input support provided by Reline, fall back to Readline.
  def _multiline_with_fallback
    query = _multiline
    query = _fallback if query[:status] == :fail

    query
  end

  def _multiline
    begin
      require 'reline' unless defined?(::Reline)
    rescue ::LoadError => e
      elog('Failed to load Reline', e)
      return { status: :fail, errors: [e] }
    end

    stop_words = %w[stop s exit e end quit q].freeze

    finished = false
    begin
      prompt_proc_before = ::Reline.prompt_proc
      ::Reline.prompt_proc = proc { |line_buffer| line_buffer.each_with_index.map { |_line, i| i > 0 ? 'SQL *> ' : 'SQL >> ' } }

      # We want to do this in a loop
      raw_query = ::Reline.readmultiline('SQL >> ', use_history = true) do |multiline_input|
        # The user pressed ctrl + c or ctrl + z and wants to background our SQL prompt
        return { status: :exit, result: nil } unless self.interacting

        # In the case only a stop word was input, exit out of the REPL shell
        finished = (multiline_input.split.count == 1 && stop_words.include?(multiline_input.split.last))

        finished || multiline_input.split.last&.end_with?(';')
      end
    rescue ::StandardError => e
      elog('Failed to get multi-line SQL query from user', e)
    ensure
      ::Reline.prompt_proc = prompt_proc_before
    end

    if finished
      self.interacting = false
      return { status: :exit, result: nil }
    end

    { status: :success, result: raw_query }
  end

  def _fallback
    stop_words = %w[stop s exit e end quit q].freeze
    line_buffer = []
    while (line = ::Readline.readline(prompt = line_buffer.empty? ? 'SQL >> ' : 'SQL *> ', add_history = true))
      return { status: :exit, result: nil } unless self.interacting

      if stop_words.include? line.chomp.downcase
        self.interacting = false
        return { status: :exit, result: nil }
      end

      next if line.empty?

      line_buffer.append line

      break if line.end_with? ';'
    end

    { status: :success, result: line_buffer.join }
  end

  attr_accessor :on_log_proc, :client_dispatcher

end

end
end
end
end
