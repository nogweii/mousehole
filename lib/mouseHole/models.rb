module MouseHole::Models

  class App < Base
    attr_accessor :klass
    serialize :matches
  end

  class CreateMouseHole < V 1.0
    def self.up
      create_table :mousehole_apps do |t|
        t.column :id,         :integer,  :null => false
        t.column :script,     :string
        t.column :uri,        :string
        t.column :active,     :integer,  :null => false, :default => 1
        t.column :matches,    :text
        t.column :created_at, :timestamp
      end
    end
    def self.down
      drop_table :mousehole_apps
    end
  end

end
