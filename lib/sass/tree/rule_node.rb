require 'pathname'

module Sass::Tree
  class RuleNode < Node
    # The character used to include the parent selector
    PARENT = '&'

    # The CSS selectors for this rule.
    # The type of this variable varies based on whether
    # this node's tree has had \{Tree::Node#perform} called or not.
    #
    # Before \{Tree::Node#perform} has been called,
    # it's an array of strings.
    # Each string is a selector line, and the lines are meant to be separated by commas.
    # For example,
    #
    #     foo, bar, baz,
    #     bip, bop, bup
    #
    # would be
    #
    #     ["foo, bar, baz",
    #      "bip, bop, bup"]
    #
    # After \{Tree::Node#perform},
    # each selector line is parsed for individual comma-separation,
    # so it's an array of arrays of strings.
    # For example,
    #
    #     foo, bar, baz,
    #     bip, bop, bup
    #
    # would be
    #
    #     [["foo", "bar", "baz"],
    #      ["bip", "bop", "bup"]]
    #
    # @return [Array<String>, Array<Array<String>>]
    attr_accessor :rules

    # @param rule [String] The first CSS rule. See \{#rules}
    # @param options [Hash<Symbol, Object>] An options hash;
    #   see [the Sass options documentation](../../Sass.html#sass_options)
    def initialize(rule, options)
      @rules = [rule]
      super(options)
    end

    # Compares the contents of two rules.
    #
    # @param other [Object] The object to compare with
    # @return [Boolean] Whether or not this node and the other object
    #   are the same
    def ==(other)
      self.class == other.class && rules == other.rules && super
    end

    # Adds another {RuleNode}'s rules to this one's.
    #
    # @param node [RuleNode] The other node
    def add_rules(node)
      @rules += node.rules
    end

    # @return [Boolean] Whether or not this rule is continued on the next line
    def continued?
      @rules.last[-1] == ?,
    end

    # Computes the CSS for the rule.
    #
    # @param tabs [Fixnum] The level of indentation for the CSS
    # @param super_rules [Array<Array<String>>] The rules for the parent node
    #   (see \{#rules}), or `nil` if there are no parents
    # @return [String] The resulting CSS
    # @raise [Sass::SyntaxError] if the rule has no parents but uses `&`
    def to_s(tabs, super_rules = nil)
      resolve_parent_refs!(super_rules)

      attributes = []
      sub_rules = []

      rule_separator = @style == :compressed ? ',' : ', '
      line_separator = [:nested, :expanded].include?(@style) ? ",\n" : rule_separator
      rule_indent = '  ' * (tabs - 1)
      per_rule_indent, total_indent = [:nested, :expanded].include?(@style) ? [rule_indent, ''] : ['', rule_indent]

      total_rule = total_indent + @rules.map do |line|
        per_rule_indent + line.join(rule_separator)
      end.join(line_separator)

      children.each do |child|
        if child.is_a? RuleNode
          sub_rules << child
        else
          attributes << child
        end
      end

      to_return = ''
      if !attributes.empty?
        old_spaces = '  ' * (tabs - 1)
        spaces = '  ' * tabs
        if @options[:line_comments] && @style != :compressed
          to_return << "#{old_spaces}/* line #{line}"

          if filename
            relative_filename = if @options[:css_filename]
              begin
                Pathname.new(filename).relative_path_from(  
                  Pathname.new(File.dirname(@options[:css_filename]))).to_s
              rescue ArgumentError
                nil
              end
            end
            relative_filename ||= filename
            to_return << ", #{relative_filename}"
          end

          to_return << " */\n"
        end

        if @style == :compact
          attributes = attributes.map { |a| a.to_s(1) }.select{|a| a && a.length > 0}.join(' ')
          to_return << "#{total_rule} { #{attributes} }\n"
        elsif @style == :compressed
          attributes = attributes.map { |a| a.to_s(1) }.select{|a| a && a.length > 0}.join(';')
          to_return << "#{total_rule}{#{attributes}}"
        else
          attributes = attributes.map { |a| a.to_s(tabs + 1) }.select{|a| a && a.length > 0}.join("\n")
          end_attrs = (@style == :expanded ? "\n" + old_spaces : ' ')
          to_return << "#{total_rule} {\n#{attributes}#{end_attrs}}\n"
        end
      end

      tabs += 1 unless attributes.empty? || @style != :nested
      sub_rules.each do |sub|
        to_return << sub.to_s(tabs, @rules)
      end

      to_return
    end

    protected

    # Runs any SassScript that may be embedded in the rule,
    # and parses the selectors for commas.
    #
    # @param environment [Sass::Environment] The lexical environment containing
    #   variable and mixin values
    def perform!(environment)
      @rules = @rules.map {|r| parse_selector(interpolate(r, environment))}
      super
    end

    private

    def resolve_parent_refs!(super_rules)
      if super_rules.nil?
        @rules.each do |line|
          line.map! do |rule|
            if rule.include?(:parent)
              raise Sass::SyntaxError.new("Base-level rules cannot contain the parent-selector-referencing character '#{PARENT}'.", self.line)
            end

            rule.join
          end.compact!
        end
        return
      end

      new_rules = []
      super_rules.each do |super_line|
        @rules.each do |line|
          new_rules << []

          super_line.each do |super_rule|
            line.each do |rule|
              rule.unshift(:parent, " ") unless rule.include?(:parent)

              new_rules.last << rule.map do |segment|
                next segment unless segment == :parent
                super_rule
              end.join
            end
          end
        end
      end
      @rules = new_rules
    end

    def parse_selector(text)
      scanner = StringScanner.new(text)
      rules = [[]]

      while scanner.rest?
        rules.last << scanner.scan(/[^",&]*/)
        case scanner.scan(/./)
        when '&'; rules.last << :parent
        when ','
          scanner.scan(/\s*/)
          rules << [] if scanner.rest?
        when '"'
          rules.last << '"' << scanner.scan(/([^"\\]|\\.)*/)
          # We don't want to enforce that strings are closed,
          # but we do want to consume quotes or trailing backslashes.
          rules.last << scanner.scan(/./) if scanner.rest?
        end
      end

      rules.map! do |l|
        Haml::Util.merge_adjacent_strings(l).reject {|r| r.is_a?(String) && r.empty?}
      end

      rules
    end
  end
end
