module ES
  class Indexer

    ##################
    # CLASS METHODS
    ##################

    def self.klass
      raise "Must be defined in subclass"
    end

    def self.delete_index
      if $elasticsearch.indices.exists(index: index_name)
        $elasticsearch.indices.delete(index: index_name)
      end
    end

    def self.create_index
      $elasticsearch.indices.create(
        index: index_name,
        type: document_type,
        body: {
          mapping: mapping
        }
      )
    end

    def self.mapping
      {
        document_type => {
          properties: {
            #add properties in subclasses
          }
        }
      }
    end

    def self.index_all
      delete_index
      create_index
      total = (klass.constantize.count / 1000) + 1
      i = 1
      klass.constantize.find_in_batches do |group|
        puts "Reindexing batch #{i} of #{total}"
        self.new(group.map(&:id)).index_documents
        i += 1
      end
    end

    def self.index_name
      "ao3_#{Rails.env}_#{klass.underscore.pluralize}"
    end

    def self.document_type
      klass.underscore
    end

    ####################
    # INSTANCE METHODS
    ####################     

    attr_reader :ids

    def initialize(ids)
      @ids = ids
    end

    def klass
      self.class.klass
    end

    def index_name
      self.class.index_name
    end

    def document_type
      self.class.document_type
    end

    def objects
      @objects ||= klass.constantize.where(id: ids).inject({}) do |h, obj|
        h.merge(obj.id => obj)
      end
    end

    def batch
      @batch = []
      ids.each do |id|
        object = objects[id.to_i]
        if object.present?
          @batch << { index: routing_info(id) }
          @batch << document(object)
        else
          @batch << { delete: routing_info(id) }
        end
      end
      @batch
    end

    def index_documents
      $elasticsearch.bulk(body: batch)
    end

    def routing_info(id)
      {
        '_index' => index_name,
        '_type' => document_type,
        '_id' => id
      }
    end

    def document(object)
      object.as_json(root: false)
    end
  end
end
