module MouseHole::Models
    class App < Base
        attr_accessor :klass
        serialize :matches
    end

    def self.create_schema
        unless App.table_exists?
            ActiveRecord::Schema.define do
                create_table :mousehole_apps do |t|
                    t.column :id,         :integer,  :null => false
                    t.column :script,     :string
                    t.column :uri,        :string
                    t.column :active,     :integer,  :null => false, :default => 1
                    t.column :matches,    :text
                    t.column :created_at, :timestamp
                end
            end
        end
    end
end
