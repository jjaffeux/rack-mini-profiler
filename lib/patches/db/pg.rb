# PG patches, keep in mind exec and async_exec have a exec{|r| } semantics that is yet to be implemented
class PG::Result
  alias_method :each_without_profiling, :each
  alias_method :values_without_profiling, :values

  def values(*args, &blk)
    return values_without_profiling(*args, &blk) unless defined?(@miniprofiler_sql_id)
    mp_report_sql do
      values_without_profiling(*args ,&blk)
    end
  end

  def each(*args, &blk)
    return each_without_profiling(*args, &blk) unless defined?(@miniprofiler_sql_id)
    mp_report_sql do
      each_without_profiling(*args, &blk)
    end
  end

  def mp_report_sql(&block)
    start        = Time.now
    result       = yield
    elapsed_time = SqlPatches.elapsed_time(start)
    @miniprofiler_sql_id.report_reader_duration(elapsed_time)
    result
  end
end

class PG::Connection
  alias_method :exec_without_profiling, :exec
  alias_method :async_exec_without_profiling, :async_exec
  alias_method :exec_prepared_without_profiling, :exec_prepared
  alias_method :send_query_prepared_without_profiling, :send_query_prepared
  alias_method :prepare_without_profiling, :prepare

  def prepare(*args,&blk)
    # we have no choice but to do this here,
    # if we do the check for profiling first, our cache may miss critical stuff

    @prepare_map ||= {}
    @prepare_map[args[0]] = args[1]
    # dont leak more than 10k ever
    @prepare_map = {} if @prepare_map.length > 1000

    return prepare_without_profiling(*args,&blk) unless SqlPatches.should_measure?
    prepare_without_profiling(*args,&blk)
  end

  def exec(*args,&blk)
    return exec_without_profiling(*args,&blk) unless SqlPatches.should_measure?

    start        = Time.now
    result       = exec_without_profiling(*args,&blk)
    elapsed_time = SqlPatches.elapsed_time(start)
    record       = ::Rack::MiniProfiler.record_sql(args[0], elapsed_time, get_binds(*args))
    result.instance_variable_set("@miniprofiler_sql_id", record) if result

    result
  end

  def exec_prepared(*args,&blk)
    return exec_prepared_without_profiling(*args,&blk) unless SqlPatches.should_measure?

    start        = Time.now
    result       = exec_prepared_without_profiling(*args,&blk)
    elapsed_time = SqlPatches.elapsed_time(start)
    mapped       = args[0]
    mapped       = @prepare_map[mapped] || args[0] if @prepare_map
    record       = ::Rack::MiniProfiler.record_sql(mapped, elapsed_time, get_binds(mapped, args[1]))
    result.instance_variable_set("@miniprofiler_sql_id", record) if result

    result
  end

  def send_query_prepared(*args,&blk)
    return send_query_prepared_without_profiling(*args,&blk) unless SqlPatches.should_measure?

    start        = Time.now
    result       = send_query_prepared_without_profiling(*args,&blk)
    elapsed_time = SqlPatches.elapsed_time(start)
    mapped       = args[0]
    mapped       = @prepare_map[mapped] || args[0] if @prepare_map
    record       = ::Rack::MiniProfiler.record_sql(mapped, elapsed_time, get_binds(mapped, args[1]))
    result.instance_variable_set("@miniprofiler_sql_id", record) if result

    result
  end

  def async_exec(*args,&blk)
    return async_exec_without_profiling(*args,&blk) unless SqlPatches.should_measure?

    start        = Time.now
    result       = exec_without_profiling(*args,&blk)
    elapsed_time = SqlPatches.elapsed_time(start)
    record       = ::Rack::MiniProfiler.record_sql(args[0], elapsed_time, get_binds(*args))
    result.instance_variable_set("@miniprofiler_sql_id", record) if result

    result
  end
  
  def get_binds(*args)
    return if args[1].nil?
    hh = {}
    if args[0].match(/\(\$\d/) then
      arr = args[0].match(/\((\"\w+\",?\s?)+\)/).to_s.gsub!(/[",()]/, '').split #regular selects list of names from sql query, for ex. ("name1", "name2", "name3")
    end   
    args[1].each_index do |i|
      if arr then
        hh[arr[i]]=args[1][i]
      else
        var = args[0].match(/[^\s\.]+\s?=?\s\$#{i+1}/).to_s.split[0] #regular selects param name from sql query, like for ex. "name1" = $1
        var.gsub!(/["]/, '') if var
        hh[var]=args[1][i]
      end
    end
    return hh
  end
  
  alias_method :query, :exec
end
