module MouseHole::Models

  class App < Base
    has_many :blocks
    attr_accessor :klass
    serialize :matches
  end

  class Block < Base
    belongs_to :app
    acts_as_list
    serialize :config
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

  class CreateDoorway < V 1.01
    def self.up
      create_table :mousehole_blocks do |t|
        t.column :id,         :integer,  :null => false
        t.column :app_id,     :integer,  :null => false
        t.column :title,      :string
        t.column :position,   :integer
        t.column :config,     :text
        t.column :created_at, :timestamp
      end
    end
    def self.down
      drop_table :mousehole_blocks
    end
  end

end
