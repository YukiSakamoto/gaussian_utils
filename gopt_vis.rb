#!/usr/bin/ruby
# -*- coding: utf-8 -*-
require "gnuplot"
require 'optparse'


def read_energies(filename, pattern, awk_index)
	retval = []
	if File.exist?(filename)
		#results = File.readlines(filename).grep(/SCF Done/)
		results = File.readlines(filename).grep(pattern)
		retval = results.map { |conv_statement| conv_statement.split()[awk_index] }
	else
		raise "No such files: #{filename}"
	end
	return retval
end

def calc_relative_energies(energies, std_index = 0, scale_factor = 1.0)
	return energies.map{|x| (x - energies[std_index]) * scale_factor}
end

settings = {
	# Option flags => Default values
	:output_type => 0,	# 0: screen, 1: file as png
	:output_name => "",
	:type => :scf,
	:pattern => %r{SCF Done},
	:awk_index => 4,
	:files => [],
	:scale => 627.5095,
	:unit  => "kcal/mol",
	:ylabel=> "Energies",
	:relative => true,
}

# Option Parsing and Flag setting
OptionParser.new do |opt|
	# Output Settings
	opt.on('-o FILENAME', 'save as png file'){|outfile| 
		unless File.extname(outfile) == ".png" then raise "#{outfile} is invalid file name. Only png is supported" end
		settings[:output_type] = 1; settings[:output_name] = outfile
	}
	# Type Settings
	opt.on('-m', '--oniom', 'plot Extrapolated Energies from ONIOM optimization log files'){
		settings[:type] = :oniom
	}
	opt.on('-g', '--grad', 'plot RMS Gradient Norm') {
		settings[:type] = :grad
	}
	# Unit Settigns
	unit_type = :normal
	opt.on('-u UNIT', 'Unit for plot energies, hartree or eV') { |unit_name|
		if unit_name.casecmp("hartree") == 0
			unit_type = :hartree
		elsif unit_name.casecmp("eV") == 0
			unit_type = :ev
		else
			STDERR.write("Warning: Unknown Unit\n")
		end
	}
	opt.parse!(ARGV)

	settings[:files] = ARGV
	case settings[:type]
	when :oniom
		settings[:pattern] = %r{extrapolated energy}
		settings[:awk_index] = 4
		settings[:ylabel] = "Extrapolated Energies"
		settings[:relative] = true
	when :grad
		settings[:pattern] = %r{Internal  Forces:}
		settings[:awk_index] = 5
		settings[:ylabel] = "RMS Gradient Norm"
		settings[:unit]   = "Hartree/Bohr"
		settings[:scale]  = 1.0
		settings[:relative] = false
		if unit_type != :normal
			STDERR.write("Unit settings will be ignored\n")
		end
	else
		settings[:pattern] = %r{SCF Done}
		settings[:awk_index] = 4
		settings[:ylabel] = "SCF Energies"
		settings[:relative] = true
	end

	if settings[:type] != :grad
		case unit_type
		when :kcal, :normal
			settings[:scale] = 627.5095; settings[:unit] = "kcal/mol"
		when :hartree
			settings[:scale] = 1.0; settings[:unit] = "a.u."
		when :ev
			settings[:scale] = 27.2114; settings[:unit] = "eV"
		else
			raise "Unknown Unit Conversion"
		end
	end

	if settings[:unit].class == String && settings[:unit].length != 0
		settings[:ylabel] += " [#{settings[:unit]}]"
	end
end

all_energies = []
steps = []

# Read all files
settings[:files].each do |logfile|
	energies = read_energies(logfile, settings[:pattern], settings[:awk_index])
	if energies.length == 0
		STDERR.write("Warning: #{logfile} contains no convergence statement\n")
	end
	all_energies += energies
	steps << energies.length
end

if all_energies.length == 0
	raise "Error: No data found"
end

if settings[:relative] == true
	plot_values = calc_relative_energies(all_energies.map{|x|x.to_f} , 0, settings[:scale])
else
	plot_values = all_energies.map{|x| x.to_f * settings[:scale]}
end

Gnuplot.open do |gp|
  Gnuplot::Plot.new(gp) do |plot|
	  # Destination setting
	  if settings[:output_type] == 1
		  plot.terminal  "png"
		  plot.output    settings[:output_name]
	  end
	  plot.xrange "[0:#{all_energies.length}]"
	  plot.title  "Optimization process"
	  plot.xlabel "Optimization steps"
	  plot.ylabel(settings[:ylabel])

	  plot.mytics 2
	  plot.grid "xtics ytics mytics"

	  plot.data << Gnuplot::DataSet.new(plot_values) do |ds|
		  ds.with      = "lines lc black"
		  ds.linewidth = 1 
		  ds.title     = "All steps"
	  end
	
	  start = 0
	  steps.each_with_index do |step,idx|
		  if step == 0 then next end
		  range = (start...start+step).to_a
		  plot.data << Gnuplot::DataSet.new([range, plot_values[start,start+step] ]) do |ds|
			  ds.with = "points pt 7 ps 0.5"
			  #ds.pointsize = 0.5
			  ds.title = settings[:files][idx].gsub("_", "-")
		  end
		  start += step
	  end
  end
end

