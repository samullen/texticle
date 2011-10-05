class Texticle::FullTextIndexer
  def generate_migration
    stream_output do |io|
      io.puts(<<-MIGRATION)
class FullTextSearch < ActiveRecord::Migration
  def self.up
    execute(<<-SQL.strip)
      #{up_migration}
    SQL
  end

  def self.down
    execute(<<-SQL.strip)
      #{down_migration}
    SQL
  end
end
MIGRATION
    end
  end

  def stream_output(now = Time.now.utc, &block)
    if !@output_stream && Object.const_defined?(:Rails)
      File.open(migration_file_name(now), 'w', &block)
    else
      @output_stream ||= $stdout

      yield @output_stream
    end
  end

  private

  def migration_file_name(now = Time.now.utc)
    File.join(Rails.root, 'db', 'migrate',"#{now.strftime('%Y%m%d%H%M%S')}_full_text_search.rb")
  end

  def up_migration
    migration_with_type(:up)
  end

  def down_migration
    migration_with_type(:down)
  end

  def migration_with_type(type)
    sql_lines = ''

    for_each_indexable_model do |model|
      model.indexable_columns.each do |column|
        sql_lines << drop_index_sql_for(model, column)
        sql_lines << create_index_sql_for(model, column) if type == :up
      end
    end

    sql_lines.strip.gsub("\n","\n      ")
  end

  def drop_index_sql_for(model, column)
    "DROP index IF EXISTS #{index_name_for(model, column)};\n"
  end

  def create_index_sql_for(model, column)
    # The spacing gets sort of wonky in here.

    <<-SQL
CREATE index #{index_name_for(model, column)}
  ON #{model.table_name}
  USING gin(to_tsvector("#{dictionary}", "#{model.table_name}"."#{column}"::text));
SQL
  end

  def index_name_for(model, column)
    "#{model.table_name}_#{column}_fts_idx"
  end

  def for_each_indexable_model(&block)
    ObjectSpace.each_object do |obj|
      block.call(obj) if obj.respond_to?(:indexable_columns)
    end
  end

  def dictionary
    Texticle.searchable_language
  end

  # old bullshit that will be deleted:

#   def old_rake_task_stuff
#     now = Time.now.utc
#     filename = "#{now.strftime('%Y%m%d%H%M%S')}_full_text_search_#{now.to_i}.rb"
# 
#     File.open(File.join(Rails.root, 'db', 'migrate', filename), 'wb') do |migration_file|
#       up_sql_statements = []
#       down_sql_statements = []
# 
#       Dir[File.join(Rails.root, 'app', 'models', '**/*.rb')].each do |model_file|
#         klass = Texticle::FullTextIndex.find_constant_of(model_file)
# 
#         if klass.respond_to?(:full_text_indexes)
#           klass.full_text_indexes.each do |fti|
#             fti.up_sql_statements << fti.destroy_sql
#             fti.up_sql_statements << fti.create_sql
#             fti.down_sql_statements << fti.destroy_sql
#           end
#         end
#       end
# 
#       fh.puts "class FullTextSearch#{now.to_i} < ActiveRecord::Migration"
#       fh.puts "  def self.up"
#       insert_sql_statements_into_migration_file(up_sql_statements, fh)
#       fh.puts "  end\n"
# 
#       fh.puts "  def self.down"
#       insert_sql_statements_into_migration_file(dn_sql_statements, fh)
#       fh.puts "  end"
#       fh.puts "end"
#     end
#   end
# 
#   def insert_sql_statements_into_migration_file statements, fh
#     statements.each do |statement|
#       fh.puts <<-eostmt
#     execute(<<-'eosql'.strip)
#       #{statement}
#     eosql
#       eostmt
#     end
#   end
end
