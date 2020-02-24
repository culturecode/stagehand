require 'graphviz'

module Stagehand
  module Auditor
    class ChecklistVisualizer
      def initialize(checklist, show_all_commits: false)
        entries = checklist.affected_entries.select(&:commit_id)

        @graph = GraphViz.new( :G, :type => :graph )
        @commits = Hash.new {|hash, commit_id| hash[commit_id] = Stagehand::Staging::CommitEntry.find(commit_id) }
        nodes = Hash.new
        edges = []

        # Detect edges
        entries.group_by(&:key).each_value do |entries|
          entries.combination(2).each do |entry_a, entry_b|
            current_edge = [entry_a, entry_b]
            next if edges.detect {|edge| edge.sort == current_edge.sort }
            next if same_node?(entry_a, entry_b)
            next if same_subject?(entry_a, entry_b)
            edges << current_edge
          end
        end

        # Create Subgraph nodes for commits with connections to other subjects
        entries = edges.flatten.uniq unless show_all_commits
        entries.group_by {|entry| commit_subject(entry) }.each do |subject, entries|
          subgraph = create_subgraph(subject, @graph)
          entries.each do |entry|
            nodes[entry] = create_node(entry, subgraph)
          end
        end

        # Create deduplicate edge data in case multiple entries for the same record were part of a single commit
        edges = edges.map do |entry_a, entry_b|
          [[nodes[entry_a], nodes[entry_b]], label: edge_label(entry_a, entry_b)]
        end

        # Create edges
        edges.uniq.each do |(node_a, node_b), options|
          create_edge(node_a, node_b, options)
        end
      end

      def output(file_name, format: File.extname(file_name)[1..-1])
        @graph.output(format => file_name)
        File.open(file_name)
      end

      private

      def create_subgraph(subject, graph)
        graph.add_graph("cluster_#{subject}", :label => subject, :style => :filled, :color => :lightgrey)
      end

      def create_edge(node_a, node_b, options = {})
        @graph.add_edges(node_a, node_b, options.reverse_merge(:color => :red, :fontcolor => :red))
      end

      def create_node(entry, graph)
        graph.add_nodes(node_name(entry), :shape => :rect, :style => :filled, :fillcolor => :white)
      end

      def edge_label(entry_a, entry_b)
        pretty_key(entry_a)
      end

      def same_node?(entry_a, entry_b)
        node_name(entry_a) == node_name(entry_b)
      end

      def same_subject?(entry_a, entry_b)
        commit_subject(entry_a) == commit_subject(entry_b)
      end

      def commit_subject(entry)
        pretty_key(@commits[entry.commit_id])
      end

      def node_name(entry)
        "Commit #{entry.commit_id}"
      end

      def pretty_key(entry)
        "#{entry.table_name.classify} #{entry.record_id}"
      end
    end
  end
end
