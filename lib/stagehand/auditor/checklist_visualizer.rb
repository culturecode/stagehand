require 'graphviz'

module Stagehand
  module Auditor
    class ChecklistVisualizer
      def initialize(checklist)
        entries = checklist.affected_entries.select(&:commit_id)

        @graph = GraphViz.new( :G, :type => :graph );
        @commits = Hash.new {|hash, commit_id| hash[commit_id] = Stagehand::Staging::CommitEntry.find(commit_id) }
        @nodes = Hash.new
        edges = Set.new

        entries.group_by {|entry| commit_subject(entry) }.each do |subject, entries|
          subgraph = create_subgraph(subject, @graph)
          entries.each do |entry|
            @nodes[entry] = create_node(entry, subgraph)
          end
        end

        entries.group_by(&:key).each_value do |entries|
          entries.combination(2).each do |entry_a, entry_b|
            key = edge_key(entry_a, entry_b)
            next if edges.include?(key)
            next if @nodes[entry_a] == @nodes[entry_b]

            edges << key
            unless same_subject?(entry_a, entry_b)
              create_edge(entry_a, entry_b, :color => :red, :fontcolor => :red, :label => edge_label(entry_a, entry_b))
            end
          end
        end
      end

      def output(output_file_name)
        @graph.output( :png => "#{output_file_name}.png" )
      end

      private

      def create_subgraph(subject, graph)
        graph.add_graph("cluster_#{subject}", :label => subject, :style => :filled, :color => :lightgrey)
      end

      def create_edge(entry_a, entry_b, options = {})
        @graph.add_edges(@nodes[entry_a], @nodes[entry_b], options)
      end

      def create_node(entry, graph)
        graph.add_nodes(node_name(entry), :shape => :rect, :style => :filled, :fillcolor => :white)
      end

      def node_name(entry)
        "Commit #{entry.commit_id}"
      end

      def edge_key(entry_a, entry_b)
        [node_name(entry_a), node_name(entry_b)].sort
      end

      def edge_label(entry_a, entry_b)
        pretty_key(entry_a)
      end

      def commit_subject(entry)
        pretty_key(@commits[entry.commit_id])
      end

      def same_subject?(entry_a, entry_b)
        commit_subject(entry_a) == commit_subject(entry_b)
      end

      def pretty_key(entry)
        "#{entry.table_name.classify} #{entry.record_id}"
      end
    end
  end
end
