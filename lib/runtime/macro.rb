# Quotations taken from the R5RS spec
# http://www.schemers.org/Documents/Standards/R5RS/HTML/r5rs-Z-H-7.html
module Heist
  class Runtime
    
    class Macro < MetaFunction
      ELLIPSIS = '...'
      
      def initialize(*args)
        super
        @renames = {}
      end
      
      # TODO:   * throw an error if no rules match
      def call(scope, cells)
        rule, matches = *rule_for(cells, scope)
        return nil unless rule
        puts "TEMPLATE: #{rule.last}"
        expanded = expand_template(rule.last, matches)
        puts "EXPANDED: #{expanded}"
        Expansion.new(expanded)
      end
      
    private
      
      def rule_for(cells, scope)
        @body.each do |rule|
          puts "\nRULE: #{rule.first} : #{cells}"
          matches = rule_matches(rule.first[1..-1], cells)
          return [rule, matches] if matches
        end
        nil
      end
      
      # More formally, an input form F matches a pattern P if and only if:
      # 
      #     * P is a non-literal identifier; or
      #     * P is a literal identifier and F is an identifier with the
      #       same binding; or
      #     * P is a list (P1 ... Pn) and F is a list of n forms that match
      #       P1 through Pn, respectively; or
      #     * P is an improper list (P1 P2 ... Pn . Pn+1) and F is a list
      #       or improper list of n or more forms that match P1 through Pn,
      #       respectively, and whose nth 'cdr' matches Pn+1; or
      #     * P is of the form (P1 ... Pn Pn+1 <ellipsis>) where <ellipsis>
      #       is the identifier '...' and F is a proper list of at least n forms,
      #       the first n of which match P1 through Pn, respectively, and
      #       each remaining element of F matches Pn+1; or
      #     * P is a vector of the form #(P1 ... Pn) and F is a vector of n
      #       forms that match P1 through Pn; or
      #     * P is of the form #(P1 ... Pn Pn+1 <ellipsis>) where <ellipsis>
      #       is the identifier '...' and F is a vector of n or more forms the
      #       first n of which match P1 through Pn, respectively, and each
      #       remaining element of F matches Pn+1; or
      #     * P is a datum and F is equal to P in the sense of the 'equal?'
      #       procedure.
      # 
      # It is an error to use a macro keyword, within the scope of its
      # binding, in an expression that does not match any of the patterns.
      # 
      def rule_matches(pattern, input, matches = Matches.new, depth = 0)
        case pattern
        
          when List then
            return nil unless List === input
            idx = 0
            pattern.each_with_index do |token, i|
              next if token.to_s == ELLIPSIS
              followed_by_ellipsis = (pattern[i+1].to_s == ELLIPSIS)
              dx = followed_by_ellipsis ? 1 : 0
              
              consume = lambda { rule_matches(token, input[idx], matches, depth + dx) }
              return nil unless value = consume[]
              next if value == :nothing
              idx += 1
              
              idx += 1 while idx < input.size &&
                             followed_by_ellipsis &&
                             consume[]
            end
            puts "CONSUMED: #{idx} of #{input.size}"
            return nil unless idx == input.size
        
          when Identifier then
            matches.put(depth, pattern, input)
            return :nothing if input.nil?
        
          else
            return pattern == input ? true : nil
        end
        matches
      end
      
      # When a macro use is transcribed according to the template of the
      # matching <syntax rule>, pattern variables that occur in the template
      # are replaced by the subforms they match in the input. Pattern variables
      # that occur in subpatterns followed by one or more instances of the
      # identifier '...' are allowed only in subtemplates that are followed
      # by as many instances of '...'. They are replaced in the output by all
      # of the subforms they match in the input, distributed as indicated. It
      # is an error if the output cannot be built up as specified.
      # 
      # Identifiers that appear in the template but are not pattern variables
      # or the identifier '...' are inserted into the output as literal
      # identifiers. If a literal identifier is inserted as a free identifier
      # then it refers to the binding of that identifier within whose scope
      # the instance of 'syntax-rules' appears. If a literal identifier is
      # inserted as a bound identifier then it is in effect renamed to prevent
      # inadvertent captures of free identifiers.
      # 
      def expand_template(template, matches, depth = 0)
        case template
        
          when List then
            result = List.new
            template.each_with_index do |cell, i|
              next if cell.to_s == ELLIPSIS
              followed_by_ellipsis = (template[i+1].to_s == ELLIPSIS)
              
              dx = followed_by_ellipsis ? 1 : 0
              n = followed_by_ellipsis ? matches.repeats(depth + dx) : 1
              
              n.times do
                value = expand_template(cell, matches, depth + dx)
                result << value unless value.nil?
              end
            end
            result
        
          when Identifier then
            matches.defined?(depth, template) ?
                matches.get(depth, template) :
                @scope.defined?(template) ?
                    Binding.new(template, @scope) :
                    rename(template)
        
          else
            template
        end
      end
      
      def rename(id)
        @renames[id.to_s] ||= Identifier.new("::#{id}::")
      end
      
      class Expansion
        attr_reader :expression
        def initialize(expression)
          @expression = expression
        end
      end
      
      class Splice < Array
        def initialize(*args)
          super(*args)
          @index = 0
        end
        
        def shift
          value = self[@index]
          @index += 1
          @index = 0 if @index >= size
          value
        end
      end
      
      class Matches
        def initialize
          @depths = {}
        end
        
        def put(depth, name, expression)
          puts "PUT: #{depth}/#{name}"
          @depths[depth] ||= {}
          scope = @depths[depth]
          scope[name.to_s] ||= Splice.new
          scope[name.to_s] << expression
        end
        
        def get(depth, name)
          "GET #{depth}/#{name}"
          @depths[depth][name.to_s].shift
        end
        
        def defined?(depth, name)
          "DEFINED? #{depth}/#{name}"
          @depths[depth] && @depths[depth].has_key?(name.to_s)
        end
        
        def repeats(depth)
          # TODO complain if sets are mismatched
          @depths[depth].map { |k,v| v.size }.uniq.first
        end
      end
    end
    
  end
end

