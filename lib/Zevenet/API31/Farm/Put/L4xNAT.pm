###############################################################################
#
#    Zevenet Software License
#    This file is part of the Zevenet Load Balancer software package.
#
#    Copyright (C) 2014-today ZEVENET SL, Sevilla (Spain)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

use strict;
use Zevenet::Farm::Base;
use Zevenet::Farm::L4xNAT::Config;

# PUT /farms/<farmname> Modify a l4xnat Farm
sub modify_l4xnat_farm # ( $json_obj, $farmname )
{
	my $json_obj = shift;
	my $farmname = shift;

	my $desc = "Modify L4xNAT farm '$farmname'";

	# Flags
	my $reload_flag  = "false";
	my $restart_flag = "false";
	my $error        = "false";
	my $status;
	my $initialStatus = &getFarmStatus( $farmname );

	# Check that the farm exists
	if ( &getFarmFile( $farmname ) == -1 )
	{
		my $msg = "The farmname $farmname does not exists.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# Get current vip & vport
	my $vip   = &getFarmVip( "vip",  $farmname );
	my $vport = &getFarmVip( "vipp", $farmname );

	my $reload_ipds = 0;
	if (exists $json_obj->{vport} || exists $json_obj->{vip} || exists $json_obj->{newfarmname})
	{
		if ( eval { require Zevenet::IPDS; } )		
		{
			$reload_ipds = 1;
			&runIPDSStopByFarm( $farmname );
			require Zevenet::Cluster;
			&runZClusterRemoteManager( 'ipds', 'stop', $farmname );
		}
	}
	
	####### Functions

	# Modify Farm's Name
	if ( exists ( $json_obj->{ newfarmname } ) )
	{
		unless ( &getFarmStatus( $farmname ) eq 'down' )
		{
			my $msg = 'Cannot change the farm name while running';
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		unless ( length $json_obj->{ newfarmname } )
		{
			my $msg = "Invalid newfarmname, can't be blank.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		if ($json_obj->{newfarmname} ne $farmname)
		{
			#Check if farmname has correct characters (letters, numbers and hyphens)
			unless ( $json_obj->{ newfarmname } =~ /^[a-zA-Z0-9\-]*$/ )
			{
				my $msg = "Invalid newfarmname.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			#Check if the new farm's name alredy exists
			my $newffile = &getFarmFile( $json_obj->{ newfarmname } );
			if ( $newffile != -1 )
			{
				my $msg = "The farm $json_obj->{newfarmname} already exists, try another name.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			#Change farm name
			require Zevenet::Farm::Action;
			my $fnchange = &setNewFarmName( $farmname, $json_obj->{ newfarmname } );
			if ( $fnchange == -1 )
			{
				my $msg = "The name of the farm can't be modified, delete the farm and create a new one.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$restart_flag = "true";
			$farmname     = $json_obj->{ newfarmname };
		}
	}

	# Modify Load Balance Algorithm
	if ( exists ( $json_obj->{ algorithm } ) )
	{
		unless ( length $json_obj->{ algorithm } )
		{
			my $msg = "Invalid algorithm, can't be blank.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		unless ( $json_obj->{ algorithm } =~ /^(leastconn|weight|prio)$/ )
		{
			my $msg = "Invalid algorithm.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		require Zevenet::Farm::Config;
		my $error = &setFarmAlgorithm( $json_obj->{ algorithm }, $farmname );
		if ( $error )
		{
			my $msg = "Some errors happened trying to modify the algorithm.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		$restart_flag = "true";
	}

	# Modify Persistence Mode
	if ( exists ( $json_obj->{ persistence } ) )
	{
		require Zevenet::Farm::Config;
		unless ( $json_obj->{ persistence } =~ /^(?:ip|)$/ )
		{
			my $msg = "Invalid persistence.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		my $persistence = $json_obj->{ persistence };
		$persistence = 'none' if $persistence eq '';

		if ( &getFarmPersistence( $farmname ) ne $persistence )
		{
			my $statusp = &setFarmSessionType( $persistence, $farmname, "" );
			if ( $statusp )
			{
				my $msg = "Some errors happened trying to modify the persistence.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$restart_flag = "true";
		}
	}

	# Modify Protocol Type
	if ( exists ( $json_obj->{ protocol } ) )
	{
		unless ( length $json_obj->{ protocol } )
		{
			my $msg = "Invalid protocol, can't be blank.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		unless ( $json_obj->{ protocol } =~ /^(all|tcp|udp|sip|ftp|tftp)$/ )
		{
			my $msg = "Invalid protocol.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		my $error = &setFarmProto( $json_obj->{ protocol }, $farmname );
		if ( $error )
		{
			my $msg = "Some errors happened trying to modify the protocol.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		if ( $json_obj->{ protocol } eq 'all' )
		{
			$json_obj->{ vport } = &getFarmVip( "vipp", $farmname );
		}

		$restart_flag = "true";
	}

	# Modify NAT Type
	if ( exists ( $json_obj->{ nattype } ) )
	{
		unless ( length $json_obj->{ nattype } )
		{
			my $msg = "Invalid nattype, can't be blank.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		unless ( $json_obj->{ nattype } =~ /^(nat|dnat)$/ )
		{
			my $msg = "Invalid nattype.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		if ( &getFarmNatType( $farmname ) ne $json_obj->{ nattype } )
		{
			my $error = &setFarmNatType( $json_obj->{ nattype }, $farmname );
			if ( $error )
			{
				my $msg = "Some errors happened trying to modify the nattype.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$restart_flag = "true";
		}
	}

	# Modify IP Adress Persistence Time To Limit
	if ( exists ( $json_obj->{ ttl } ) )
	{
		unless ( length $json_obj->{ ttl } )
		{
			my $msg = "Invalid ttl, can't be blank.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		unless ( $json_obj->{ ttl } =~ /^\d+$/ )
		{
			my $msg = "Invalid ttl.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		require Zevenet::Farm::Config;
		my $error = &setFarmMaxClientTime( 0, $json_obj->{ ttl }, $farmname );
		if ( $error )
		{
			my $msg = "Some errors happened trying to modify the ttl.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		$json_obj->{ ttl } = $json_obj->{ ttl } + 0;
		$restart_flag = "true";
	}

	if ( exists ( $json_obj->{ vip } ) )
	{
		# the ip must exist in some interface
		require Zevenet::Net::Interface;
		unless ( &getIpAddressExists( $json_obj->{ vip } ) )
		{
			my $msg = "The vip IP must exist in some interface.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
		unless ( length $json_obj->{ vip } )
		{
			my $msg = "Invalid vip, can't be blank.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}

	if ( exists ( $json_obj->{ vport } ) )
	{
		# VPORT validation
		if (
			!&getValidPort(
							$json_obj->{ vip },
							$json_obj->{ vport },
							"L4XNAT"
			)
		)
		{
			my $msg = "The virtual port must be an acceptable value and must be available.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}
	
	# Modify only vip
	if ( exists ( $json_obj->{ vip } ) && !exists ( $json_obj->{ vport } ) )
	{
		require Zevenet::Farm::Config;
		if ( &setFarmVirtualConf( $json_obj->{ vip }, $vport, $farmname ) )
		{
			my $msg = "Invalid vip.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		$restart_flag = "true";
	}

	# Modify only vport
	if ( exists ( $json_obj->{ vport } ) && !exists ( $json_obj->{ vip } ) )
	{
		require Zevenet::Farm::Config;
		if ( &setFarmVirtualConf( $vip, $json_obj->{ vport }, $farmname ) )
		{
			my $msg = "Invalid vport.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		$restart_flag = "true";
	}

	# Modify both vip & vport
	if ( exists ( $json_obj->{ vip } ) && exists ( $json_obj->{ vport } ) )
	{
		require Zevenet::Farm::Config;
		if ( &setFarmVirtualConf( $json_obj->{ vip }, $json_obj->{ vport }, $farmname ) )
		{
			my $msg = "Invalid vport or invalid vip.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		$restart_flag = "true";
	}

	# no error found, return successful response
	&zenlog( "ZAPI success, some parameters have been changed in farm $farmname." );

	if ( &getFarmStatus( $farmname ) eq 'up' )
	{
		# Reset ip rule mark when changing the farm's vip
		if ( exists $json_obj->{ vip } && $json_obj->{ vip } ne $vip )
		{
			require Zevenet::Net::Util;

			my $farm   = &getL4FarmStruct( $farmname );
			my $ip_bin = &getGlobalConfiguration( 'ip_bin' );
			# previous vip
			my $prev_vip_if_name = &getInterfaceOfIp( $vip );
			my $prev_vip_if      = &getInterfaceConfig( $prev_vip_if_name );
			my $prev_table_if =
			  ( $prev_vip_if->{ type } eq 'virtual' )
			  ? $prev_vip_if->{ parent }
			  : $prev_vip_if->{ name };
			# new vip
			my $vip_if_name = &getInterfaceOfIp( $json_obj->{ vip } );
			my $vip_if      = &getInterfaceConfig( $vip_if_name );
			my $table_if =
			  ( $vip_if->{ type } eq 'virtual' ) ? $vip_if->{ parent } : $vip_if->{ name };

			foreach my $server ( @{ $$farm{ servers } } )
			{
				my $ip_del_cmd = "$ip_bin rule add fwmark $server->{ tag } table table_$table_if";
				my $ip_add_cmd = "$ip_bin rule del fwmark $server->{ tag } table table_$prev_table_if";
				&logAndRun( $ip_add_cmd );
				&logAndRun( $ip_del_cmd );
			}
		}

		if ( eval { require Zevenet::Cluster; } )
		{
			&runZClusterRemoteManager( 'farm', 'restart', $farmname );
		}

		if ( $reload_ipds )
		{
			if ( eval { require Zevenet::IPDS::Base; } )
			{
				&runIPDSStartByFarm( $farmname );
				require Zevenet::Cluster;
				&runZClusterRemoteManager( 'ipds', 'start', $farmname );
			}
		}
	}

	my $body = {
				 description => $desc,
				 params      => $json_obj
	};

	&httpResponse({ code => 200, body => $body });
}

1;
