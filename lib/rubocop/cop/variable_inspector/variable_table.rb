# encoding: utf-8

module Rubocop
  module Cop
    module VariableInspector
      # A VariableTable manages the lifetime of all scopes and local variables
      # in a program.
      # This holds scopes as stack structure, and provides a way to add local
      # variables to current scope and find local variables by considering
      # variable visibility of the current scope.
      class VariableTable
        def initialize(hook_receiver = nil)
          @hook_receiver = hook_receiver
        end

        def invoke_hook(hook_name, *args)
          @hook_receiver.send(hook_name, *args) if @hook_receiver
        end

        def scope_stack
          @scope_stack ||= []
        end

        def push_scope(scope_node)
          scope = Scope.new(scope_node)
          invoke_hook(:before_entering_scope, scope)
          scope_stack.push(scope)
          invoke_hook(:after_entering_scope, scope)
          scope
        end

        def pop_scope
          scope = current_scope
          invoke_hook(:before_leaving_scope, scope)
          scope_stack.pop
          invoke_hook(:after_leaving_scope, scope)
          scope
        end

        def current_scope
          scope_stack.last
        end

        def current_scope_level
          scope_stack.count
        end

        def declare_variable(name, node)
          variable = Variable.new(name, node, current_scope)
          invoke_hook(:before_declaring_variable, variable)
          current_scope.variables[variable.name] = variable
          invoke_hook(:after_declaring_variable, variable)
          variable
        end

        def assign_to_variable(name, node)
          variable = find_variable(name)

          unless variable
            fail "Assigning to undeclared local variable \"#{name}\" " +
                 "at #{node.loc.expression}, #{node.inspect}"
          end

          variable.assign(node)
          mark_variable_as_captured_by_block_if_so(variable)
        end

        def reference_variable(name)
          variable = find_variable(name)

          unless variable
            fail "Referencing undeclared local variable \"#{name}\""
          end

          variable.reference!
          mark_variable_as_captured_by_block_if_so(variable)
        end

        def find_variable(name)
          name = name.to_sym

          scope_stack.reverse_each do |scope|
            variable = scope.variables[name]
            return variable if variable
            # Only block scope allows referencing outer scope variables.
            return nil unless scope.node.type == :block
          end

          nil
        end

        def variable_exist?(name)
          !find_variable(name).nil?
        end

        def accessible_variables
          scope_stack.reverse_each.reduce([]) do |variables, scope|
            variables.concat(scope.variables.values)
            break variables unless scope.node.type == :block
            variables
          end
        end

        private

        def mark_variable_as_captured_by_block_if_so(variable)
          return unless current_scope.node.type == :block
          return if variable.scope == current_scope
          variable.capture_with_block!
        end
      end
    end
  end
end
