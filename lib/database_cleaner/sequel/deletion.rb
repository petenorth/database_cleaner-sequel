require 'database_cleaner/sequel/base'
require 'database_cleaner/generic/truncation'
require 'database_cleaner/sequel/truncation'

module DatabaseCleaner::Sequel
  class Deletion < Truncation
    def disable_referential_integrity(tables)

      if ENV['DB_CLEANER_AZURE'] == 'true'
        return
      end

      case db.database_type
      when :postgres
        db.run('SET CONSTRAINTS ALL DEFERRED')
        tables_to_truncate(db).each do |table|
          db.run("ALTER TABLE \"#{table}\" DISABLE TRIGGER ALL")
        end
      when :mysql
        old = db.fetch('SELECT @@FOREIGN_KEY_CHECKS').first[:@@FOREIGN_KEY_CHECKS]
        db.run('SET FOREIGN_KEY_CHECKS = 0')
      end
      yield
    ensure
      case db.database_type
      when :postgres
        tables.each do |table|
          db.run("ALTER TABLE \"#{table}\" ENABLE TRIGGER ALL")
        end
      when :mysql
        db.run("SET FOREIGN_KEY_CHECKS = #{old}")
      end
    end

    def delete_tables(db, tables)
      tables.each do |table|
        db[table.to_sym].delete
      end
    end

    def clean
      return unless dirty?

      if ENV['DB_CLEANER_AZURE'] == 'true'
      
        records_array = ActiveRecord::Base.connection.execute %{
WITH RECURSIVE t AS (
    SELECT relnamespace as nsp, oid as tbl, null::regclass as source, 1 as level
    FROM pg_class
    WHERE relkind = 'r'
        AND relnamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace)
UNION ALL
    SELECT c.connamespace as nsp, c.conrelid as tbl, c.confrelid as source, p.level + 1
    FROM pg_constraint c
    INNER JOIN t p ON (c.confrelid = p.tbl AND c.connamespace = p.nsp)
    WHERE c.contype = 'f'
        AND c.connamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace)
)
SELECT tbl::regclass
FROM t
GROUP BY nsp, tbl
ORDER BY max(level) DESC;
        }
       
        tables = records_array.column_values(0)
        tables.each {|st| puts st}

      else

        tables = tables_to_truncate(db)       
 
      end

      db.transaction do
        disable_referential_integrity(tables) do
          delete_tables(db, tables)
        end
      end
    end
  end
end
