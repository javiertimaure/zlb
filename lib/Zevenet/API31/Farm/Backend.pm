#!/usr/bin/perl
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
use Zevenet::Farm::Core;

# POST

sub new_farm_backend    # ( $json_obj, $farmname )
{
	my $json_obj = shift;
	my $farmname = shift;

	require Zevenet::Farm::Backend;
	require Zevenet::Farm::Base;

	# Initial parameters
	my $desc = "New farm backend";

	# validate FARM NAME
	if ( &getFarmFile( $farmname ) == -1 )
	{
		my $msg = "The farmname $farmname does not exists.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# validate FARM TYPE
	my $type = &getFarmType( $farmname );

	if ( $type eq "l4xnat" )
	{
		require Zevenet::Net::Validate;

		# Get ID of the new backend
		# FIXME: Maybe make a function of this?
		my $id  = 0;
		my @run = &getFarmServers( $farmname );

		if ( @run > 0 )
		{
			foreach my $l_servers ( @run )
			{
				my @l_serv = split ( ";", $l_servers );

				if ( $l_serv[1] ne "0.0.0.0" )
				{
					if ( $l_serv[0] > $id )
					{
						$id = $l_serv[0];
					}
				}
			}

			if ( $id >= 0 )
			{
				$id++;
			}
		}

		# validate IP
		if ( ! $json_obj->{ ip } )
		{
			my $msg = "Invalid backend IP value. It cannot be in blank.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		# validate IP
		if ( !&getValidFormat( 'IPv4_addr', $json_obj->{ ip } ) )
		{
			my $msg = "Invalid backend IP value.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		# validate PORT
		unless (    &isValidPortNumber( $json_obj->{ port } ) eq 'true'
				 || $json_obj->{ port } eq '' )
		{
			my $msg = "Invalid IP address and port for a backend, it can't be blank.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		# validate PRIORITY
		if ( $json_obj->{ priority } !~ /^\d$/
			 && exists $json_obj->{ priority } )    # (0-9)
		{
			my $msg =
			  "Invalid backend priority value, please insert a value within the range 0-9.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		# validate WEIGHT
		if ( $json_obj->{ weight } !~ /^[1-9]$/
			 && exists $json_obj->{ weight } )      # 1 or higher
		{
			my $msg = "Invalid backend weight value, please insert a value form 1 to 9.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		# validate MAX_CONNS
		$json_obj->{ max_conns } = 0 unless exists $json_obj->{ max_conns };

		if ( $json_obj->{ max_conns } !~ /^[0-9]+$/ )    # (0 or higher)
		{
			my $msg =
			  "Invalid backend connection limit value, accepted values are 0 or higher.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		# Create backend
		my $status = &setFarmServer(
									 $id,
									 $json_obj->{ ip },
									 $json_obj->{ port },
									 $json_obj->{ max_conns },
									 $json_obj->{ weight },
									 $json_obj->{ priority },
									 "",
									 $farmname
		);

		if ( $status == -1 )
		{
			my $msg = "It's not possible to create the backend with ip $json_obj->{ ip }"
			  . " and port $json_obj->{ port } for the $farmname farm";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		&zenlog( "New backend created in farm $farmname with IP $json_obj->{ip}." );

		$json_obj->{ port }     += 0 if $json_obj->{ port };
		$json_obj->{ weight }   += 0 if $json_obj->{ weight };
		$json_obj->{ priority } += 0 if $json_obj->{ priority };

		my $message = "Backend added";
		my $body = {
					 description => $desc,
					 params      => {
								 id        => $id,
								 ip        => $json_obj->{ ip },
								 port      => $json_obj->{ port },
								 weight    => $json_obj->{ weight },
								 priority  => $json_obj->{ priority },
								 max_conns => $json_obj->{ max_conns },
					 },
					 message => $message,
					 status  => &getFarmVipStatus( $farmname ),
		};

		if ( eval { require Zevenet::Cluster; } )
		{
			&runZClusterRemoteManager( 'farm', 'restart', $farmname );
		}

		&httpResponse( { code => 201, body => $body } );
	}
	elsif ( $type eq "datalink" )
	{
		# get an ID
		# FIXME: Maybe make a function of this?
		my $id  = 0;
		my @run = &getFarmServers( $farmname );

		if ( @run > 0 )
		{
			foreach my $l_servers ( @run )
			{
				my @l_serv = split ( ";", $l_servers );

				if ( $l_serv[1] ne "0.0.0.0" )
				{
					if ( $l_serv[0] > $id )
					{
						$id = $l_serv[0];
					}
				}
			}

			if ( $id >= 0 )
			{
				$id++;
			}
		}

		# validate INTERFACE
		require Zevenet::Net::Interface;

		my $valid_interface;

		for my $iface ( @{ &getActiveInterfaceList() } )
		{
			next if $iface->{ vini };     # discard virtual interfaces
			next if !$iface->{ addr };    # discard interfaces without address

			if ( $iface->{ name } eq $json_obj->{ interface } )
			{
				$valid_interface = 'true';
			}
		}

		if ( !$valid_interface )
		{
			my $msg = "Invalid interface value, please insert any non-virtual interface.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		require Zevenet::Net::Validate;
		my $iface_ref = &getInterfaceConfig( $json_obj->{ interface } );
		if (
			 !&getNetValidate(
							   $iface_ref->{ addr },
							   $iface_ref->{ mask },
							   $json_obj->{ ip }
			 )
		  )
		{
			my $msg = "The IP must be in the same network than the local interface.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		# validate WEIGHT
		unless (    $json_obj->{ weight } =~ &getValidFormat( 'natural_num' )
				 || $json_obj->{ weight } == undef )    # 1 or higher or undef
		{
			my $msg = "Invalid weight value, please insert a valid weight value.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		# validate PRIORITY
		unless (    $json_obj->{ priority } =~ /^[1-9]$/
				 || $json_obj->{ priority } == undef )    # (1-9)
		{
			my $msg = "Invalid priority value, please insert a valid priority value.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		# Create backend
		my $status = &setFarmServer(
									 $id,                      $json_obj->{ ip },
									 $json_obj->{ interface }, "",
									 $json_obj->{ weight },    $json_obj->{ priority },
									 "",                       $farmname
		);

		# check error adding a new backend
		if ( $status == -1 )
		{
			&zenlog( "It's not possible to create the backend." );

			my $msg = "It's not possible to create the backend with ip $json_obj->{ ip }"
			  . " and port $json_obj->{ port } for the $farmname farm";

			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		&zenlog(
			"ZAPI success, a new backend has been created in farm $farmname with IP $json_obj->{ip}."
		);

		my $message = "Backend added";
		my $body = {
			description => $desc,
			params      => {
				  id        => $id,
				  ip        => $json_obj->{ ip },
				  interface => $json_obj->{ interface },
				  weight => ( $json_obj->{ weight } ne '' ) ? $json_obj->{ weight } + 0 : undef,
				  priority => ( $json_obj->{ priority } ne '' )
				  ? $json_obj->{ priority } + 0
				  : undef,
			},
			message => $message,
			status  => &getFarmVipStatus( $farmname ),
		};

		if ( eval { require Zevenet::Cluster; } )
		{
			&runZClusterRemoteManager( 'farm', 'restart', $farmname );
		}

		&httpResponse( { code => 201, body => $body } );
	}
	else
	{
		my $msg = "The $type farm profile can have backends in services only.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}
}

sub new_service_backend    # ( $json_obj, $farmname, $service )
{
	my $json_obj = shift;
	my $farmname = shift;
	my $service  = shift;

	# Initial parameters
	my $desc = "New service backend";

	# Check that the farm exists
	if ( &getFarmFile( $farmname ) == -1 )
	{
		my $msg = "The farmname $farmname does not exists.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# validate FARM TYPE
	my $type = &getFarmType( $farmname );

	if ( $type eq "gslb" )
	{
		require Zevenet::ELoad;
		&eload(
				module => 'Zevenet::API31::Farm::GSLB',
				func   => 'new_gslb_service_backend',
				args   => [$json_obj, $farmname, $service]
		);
	}
	elsif ( $type !~ /^https?$/ )
	{
		my $msg = "The $type farm profile does not support services.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# HTTP
	require Zevenet::Net::Validate;
	require Zevenet::Farm::Base;
	require Zevenet::Farm::HTTP::Config;
	require Zevenet::Farm::HTTP::Backend;
	require Zevenet::Farm::HTTP::Service;

	# validate SERVICE
	my @services = &getHTTPFarmServices( $farmname );
	my $found    = 0;

	foreach my $farmservice ( @services )
	{
		if ( $service eq $farmservice )
		{
			$found = 1;
			last;
		}
	}

	# Check if the provided service is configured in the farm
	if ( $found == 0 )
	{
		my $msg = "Invalid service name, please insert a valid value.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# get an ID for the new backend
	my $backendsvs = &getHTTPFarmVS( $farmname, $service, "backends" );
	my @be = split ( "\n", $backendsvs );
	my $id;

	foreach my $subl ( @be )
	{
		my @subbe = split ( ' ', $subl );
		$id = $subbe[1] + 1;
	}

	$id = 0 if $id eq '';

	# validate IP
	unless ( defined $json_obj->{ ip }
			 && &getValidFormat( 'IPv4_addr', $json_obj->{ ip } ) )
	{
		my $msg = "Invalid backend IP value, please insert a valid value.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# validate PORT
	unless ( &isValidPortNumber( $json_obj->{ port } ) eq 'true' )
	{
		&zenlog( "Invalid IP address and port for a backend, ir can't be blank." );

		my $msg = "Invalid port for a backend.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# validate WEIGHT
	unless ( !defined ( $json_obj->{ weight } )
			 || $json_obj->{ weight } =~ /^[1-9]$/ )
	{
		my $msg = "Invalid weight value for a backend, it must be 1-9.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# validate TIMEOUT
	unless ( !defined ( $json_obj->{ timeout } )
		   || ( $json_obj->{ timeout } =~ /^\d+$/ && $json_obj->{ timeout } != 0 ) )
	{
		my $msg =
		  "Invalid timeout value for a backend, it must be empty or greater than 0.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

# First param ($id) is an empty string to let function autogenerate the id for the new backend
	my $status = &setHTTPFarmServer(
									 "",
									 $json_obj->{ ip },
									 $json_obj->{ port },
									 $json_obj->{ weight },
									 $json_obj->{ timeout },
									 $farmname,
									 $service,
	);

	# check if there was an error adding a new backend
	if ( $status == -1 )
	{
		my $msg = "It's not possible to create the backend with ip $json_obj->{ ip }"
		  . " and port $json_obj->{ port } for the $farmname farm";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# no error found, return successful response
	&zenlog(
		"ZAPI success, a new backend has been created in farm $farmname in service $service with IP $json_obj->{ip}."
	);

	$json_obj->{ timeout } = $json_obj->{ timeout } + 0 if $json_obj->{ timeout };

	if ( &getFarmStatus( $farmname ) eq 'up' )
	{
		require Zevenet::Farm::Action;

		&setFarmRestart( $farmname );
	}

	my $message = "Added backend to service successfully";
	my $body = {
				 description => $desc,
				 params      => {
							 id      => $id,
							 ip      => $json_obj->{ ip },
							 port    => $json_obj->{ port } + 0,
							 weight  => $json_obj->{ weight } + 0,
							 timeout => $json_obj->{ timeout },
				 },
				 message => $message,
				 status  => &getFarmVipStatus( $farmname ),
	};

	&httpResponse( { code => 201, body => $body } );
}

# GET

#GET /farms/<name>/backends
sub backends
{
	my $farmname = shift;

	my $desc = "List backends";

	# Check that the farm exists
	if ( &getFarmFile( $farmname ) == -1 )
	{
		my $msg = "The farmname $farmname does not exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $type = &getFarmType( $farmname );

	if ( $type eq 'l4xnat' )
	{
		require Zevenet::Farm::L4xNAT::Backend;
		my $backends = &getL4FarmBackends( $farmname );

		my $body = {
					 description => $desc,
					 params      => $backends,
		};

		&httpResponse( { code => 200, body => $body } );
	}
	elsif ( $type eq 'datalink' )
	{
		require Zevenet::Farm::Datalink::Backend;
		my $backends = &getDatalinkFarmBackends( $farmname );

		my $body = {
					 description => $desc,
					 params      => $backends,
		};

		&httpResponse( { code => 200, body => $body } );
	}
	else
	{
		my $msg =
		  "The farm $farmname with profile $type does not support this request.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}
}

#GET /farms/<name>/services/<service>/backends
sub service_backends
{
	my ( $farmname, $service ) = @_;

	my $desc = "List service backends";
	my $backendstatus;

	# Check that the farm exists
	if ( &getFarmFile( $farmname ) eq '-1' )
	{
		my $msg = "The farmname $farmname does not exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $type = &getFarmType( $farmname );

	if ( $type eq 'gslb' )
	{
		require Zevenet::ELoad;
		&eload(
				module => 'Zevenet::API31::Farm::GSLB',
				func   => 'list_gslb_service_backends',
				args   => [$farmname, $service]
		);
	}

	if ( $type !~ /^https?$/ )
	{
		my $msg = "The farm profile $type does not support this request.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# HTTP
	require Zevenet::Farm::HTTP::Backend;
	require Zevenet::Farm::HTTP::Service;

	my @services_list = split ' ', &getHTTPFarmVS( $farmname );

	# check if the requested service exists
	unless ( grep { $service eq $_ } @services_list )
	{
		my $msg = "The service $service does not exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my @be = split ( "\n", &getHTTPFarmVS( $farmname, $service, "backends" ) );
	my @backends;

	# populate output array
	foreach my $subl ( @be )
	{
		my @subbe       = split ( ' ', $subl );
		my $id          = $subbe[1] + 0;
		my $maintenance = &getHTTPFarmBackendMaintenance( $farmname, $id, $service );

		if ( $maintenance != 0 )
		{
			$backendstatus = "up";
		}
		else
		{
			$backendstatus = "maintenance";
		}

		my $ip   = $subbe[3];
		my $port = $subbe[5] + 0;
		my $tout = $subbe[7];
		my $prio = $subbe[9];

		$tout = $tout eq '-' ? undef : $tout + 0;
		$prio = $prio eq '-' ? undef : $prio + 0;

		push @backends,
		  {
			id      => $id,
			status  => $backendstatus,
			ip      => $ip,
			port    => $port,
			timeout => $tout,
			weight  => $prio,
		  };
	}

	my $body = {
				 description => $desc,
				 params      => \@backends,
	};

	&httpResponse( { code => 200, body => $body } );
}

# PUT

sub modify_backends    #( $json_obj, $farmname, $id_server )
{
	my ( $json_obj, $farmname, $id_server ) = @_;

	my $desc = "Modify backend";
	my $zapierror;

	# Check that the farm exists
	if ( &getFarmFile( $farmname ) == -1 )
	{
		my $msg = "The farmname $farmname does not exists.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $error;
	my $type = &getFarmType( $farmname );

	if ( $type eq "l4xnat" )
	{
		require Zevenet::Farm::L4xNAT::Config;

		# Params
		my $l4_farm = &getL4FarmStruct( $farmname );
		my $backend;

		for my $be ( @{ $l4_farm->{ 'servers' } } )
		{
			if ( $be->{ 'id' } eq $id_server )
			{
				$backend = $be;
			}
		}

		if ( !$backend )
		{
			my $msg = "Could not find a backend with such id.";
			&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
		}

		if ( exists ( $json_obj->{ ip } ) )
		{
			unless (    $json_obj->{ ip }
					 && &getValidFormat( 'IPv4_addr', $json_obj->{ ip } ) )
			{
				my $msg = "Invalid IP.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$backend->{ vip } = $json_obj->{ ip };
		}

		if ( exists ( $json_obj->{ port } ) )
		{
			unless (    &isValidPortNumber( $json_obj->{ port } ) eq 'true'
					 || $json_obj->{ port } == undef )
			{
				my $msg = "Invalid port number.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$backend->{ vport } = $json_obj->{ port };
		}

		if ( exists ( $json_obj->{ weight } ) )
		{
			unless (    $json_obj->{ weight } =~ /^[1-9]$/
					 || $json_obj->{ weight } == undef )    # 1 or higher
			{
				my $msg =
				  "Invalid backend weight value, please insert a value form 1 to 9.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$backend->{ weight } = $json_obj->{ weight };
		}

		if ( exists ( $json_obj->{ priority } ) )
		{
			unless (    $json_obj->{ priority } =~ /^\d$/
					 || $json_obj->{ priority } == undef )    # (0-9)
			{
				my $msg =
				  "Error, trying to modify the backends in the farm $farmname, invalid priority. The higher value is 9.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$backend->{ priority } = $json_obj->{ priority };
		}

		if ( exists ( $json_obj->{ max_conns } ) )
		{
			unless ( $json_obj->{ max_conns } =~ /^\d+$/ )    # (0 or higher)
			{
				my $msg =
				  "Error, trying to modify the connection limit in the farm $farmname, invalid value.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$backend->{ max_conns } = $json_obj->{ max_conns };
		}

		my $status = &setL4FarmServer(
									   $backend->{ id },
									   $backend->{ vip },
									   $backend->{ vport },
									   $backend->{ weight },
									   $backend->{ priority },
									   $farmname,
									   $backend->{ max_conns },
		);

		if ( $status == -1 )
		{
			my $msg = "It's not possible to modify the backend with ip $json_obj->{ip}.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}
	elsif ( $type eq "datalink" )
	{
		require Zevenet::Farm::Backend;

		my @run         = &getFarmServers( $farmname );
		my $serv_values = $run[$id_server];
		my $be;

		if ( !$serv_values )
		{
			my $msg = "Could not find a backend with such id.";
			&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
		}

		(
		   undef,
		   $be->{ ip },
		   $be->{ interface },
		   $be->{ weight },
		   $be->{ priority },
		   $be->{ status }
		) = split ( ";", $serv_values );

		# Functions
		if ( exists ( $json_obj->{ ip } ) )
		{
			if ( $json_obj->{ ip } && &getValidFormat( 'IPv4_addr', $json_obj->{ ip } ) )
			{
				$be->{ ip } = $json_obj->{ ip };
			}
			else
			{
				my $msg = "Invalid IP.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}
		}

		if ( exists ( $json_obj->{ interface } ) )
		{
			require Zevenet::Net::Interface;

			my $valid_interface;

			for my $iface ( @{ &getActiveInterfaceList() } )
			{
				next if $iface->{ vini };     # discard virtual interfaces
				next if !$iface->{ addr };    # discard interfaces without address

				if ( $iface->{ name } eq $json_obj->{ interface } )
				{
					$valid_interface = 'true';
				}
			}

			unless ( $valid_interface )
			{
				my $msg = "Invalid interface.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$be->{ interface } = $json_obj->{ interface };
		}

		# check that IP is in network than interface
		require Zevenet::Net::Validate;
		my $iface_ref = &getInterfaceConfig( $be->{ interface } );
		if (
			 !&getNetValidate( $iface_ref->{ addr }, $iface_ref->{ mask }, $be->{ ip } ) )
		{
			my $msg = "The IP must be in the same network than the local interface.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		if ( exists ( $json_obj->{ weight } ) )
		{
			if ( !&getValidFormat( 'natural_num', $json_obj->{ weight } ) )    # 1 or higher
			{
				my $msg = "Invalid weight.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$be->{ weight } = $json_obj->{ weight };
		}

		if ( exists ( $json_obj->{ priority } ) )
		{
			if ( $json_obj->{ priority } !~ /^[1-9]$/ )                        # (1-9)
			{
				my $msg = "Invalid priority.";
				&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
			}

			$be->{ priority } = $json_obj->{ priority };
		}

		my $status =
		  &setFarmServer( $id_server,
						  $be->{ ip },
						  $be->{ interface },
						  "",
						  $be->{ weight },
						  $be->{ priority },
						  "", $farmname );

		if ( $status == -1 )
		{
			my $msg =
			  "It's not possible to modify the backend with IP $json_obj->{ip} and interface $json_obj->{interface}.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}
	}
	else
	{
		my $msg = "The $type farm profile has backends only in services.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	&zenlog(
		"ZAPI success, some parameters have been changed in the backend $id_server in farm $farmname."
	);

	require Zevenet::Farm::Base;
	my $message = "Backend modified";
	my $body = {
				 description => $desc,
				 params      => $json_obj,
				 message     => $message,
				 status      => &getFarmVipStatus( $farmname ),
	};

	if ( eval { require Zevenet::Cluster; } )
	{
		if ( &getFarmStatus( $farmname ) eq 'up' )
		{
			&runZClusterRemoteManager( 'farm', 'restart', $farmname );
		}
	}

	&httpResponse( { code => 200, body => $body } );
}

sub modify_service_backends    #( $json_obj, $farmname, $service, $id_server )
{
	my ( $json_obj, $farmname, $service, $id_server ) = @_;

	my $desc = "Modify service backend";

	# Check that the farm exists
	if ( &getFarmFile( $farmname ) == -1 )
	{
		my $msg = "The farmname $farmname does not exist.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $type = &getFarmType( $farmname );

	if ( $type eq "gslb" )
	{
		require Zevenet::ELoad;
		&eload(
				module => 'Zevenet::API31::Farm::GSLB',
				func   => 'modify_gslb_service_backends',
				args   => [$json_obj, $farmname, $service, $id_server]
		);
	}
	elsif ( $type !~ /^https?$/ )
	{
		my $msg = "The $type farm profile does not support services.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# HTTP
	require Zevenet::Farm::Base;
	require Zevenet::Farm::Action;
	require Zevenet::Farm::HTTP::Config;
	require Zevenet::Farm::HTTP::Backend;
	require Zevenet::Farm::HTTP::Service;

	# validate SERVICE
	my @services = &getHTTPFarmServices( $farmname );
	my $found_service = grep { $service eq $_ } @services;

	# check if the service exists
	if ( !$found_service )
	{
		my $msg = "Could not find the requested service.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# validate BACKEND
	my $backendsvs = &getHTTPFarmVS( $farmname, $service, "backends" );
	my @be_list = split ( "\n", $backendsvs );
	my $be;

	foreach my $be_line ( @be_list )
	{
		my @current_be = split ( " ", $be_line );

		if ( $current_be[1] == $id_server )    # id
		{
			$current_be[7] = undef if $current_be[7] eq '-';    # timeout
			$current_be[9] = undef if $current_be[9] eq '-';    # priority

			$be = {
					id       => $current_be[1],
					ip       => $current_be[3],
					port     => $current_be[5],
					timeout  => $current_be[7],
					priority => $current_be[9],
			};

			last;
		}
	}

	# check if the backend was found
	if ( !$be )
	{
		my $msg = "Could not find a service backend with such id.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# validate BACKEND new ip
	if ( exists ( $json_obj->{ ip } ) )
	{
		unless (    $json_obj->{ ip }
				 && &getValidFormat( 'IPv4_addr', $json_obj->{ ip } ) )
		{
			my $msg = "Invalid IP.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		$be->{ ip } = $json_obj->{ ip };
	}

	# validate BACKEND new port
	if ( exists ( $json_obj->{ port } ) )
	{
		require Zevenet::Net::Validate;

		unless ( &isValidPortNumber( $json_obj->{ port } ) eq 'true' )
		{
			my $msg = "Invalid port.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		$be->{ port } = $json_obj->{ port };
	}

	# validate BACKEND weigh
	if ( exists ( $json_obj->{ weight } ) )
	{
		unless ( $json_obj->{ weight } =~ /^[1-9]$/ )
		{
			my $msg = "Invalid weight.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		$be->{ priority } = $json_obj->{ weight };
	}

	# validate BACKEND timeout
	if ( exists ( $json_obj->{ timeout } ) )
	{
		unless ( $json_obj->{ timeout } eq ''
			   || ( $json_obj->{ timeout } =~ /^\d+$/ && $json_obj->{ timeout } != 0 ) )
		{
			my $msg = "Invalid timeout.";
			&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
		}

		$be->{ timeout } = $json_obj->{ timeout };
	}

	# apply BACKEND change
	my $status = &setHTTPFarmServer( $id_server,
									 $be->{ ip },
									 $be->{ port },
									 $be->{ priority },
									 $be->{ timeout },
									 $farmname, $service );

	# check if there was an error modifying the backend
	if ( $status == -1 )
	{
		my $msg =
		  "It's not possible to modify the backend with IP $json_obj->{ip} in service $service.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# no error found, return successful response
	&zenlog(
		"ZAPI success, some parameters have been changed in the backend $id_server in service $service in farm $farmname."
	);

	if ( &getFarmStatus( $farmname ) eq "up" )
	{
		&setFarmRestart( $farmname );
	}

	my $body = {
				 description => $desc,
				 params      => $json_obj,
				 message     => "Backend modified",
				 status      => &getFarmVipStatus( $farmname ),
	};

	if ( &getFarmStatus( $farmname ) eq "up" )
	{
		$body->{ info } =
		  "There're changes that need to be applied, stop and start farm to apply them!";
	}

	&httpResponse( { code => 200, body => $body } );
}

# DELETE

# DELETE /farms/<farmname>/backends/<backendid> Delete a backend of a Farm
sub delete_backend    # ( $farmname, $id_server )
{
	my ( $farmname, $id_server ) = @_;

	my $desc = "Delete backend";

	# validate FARM NAME
	if ( &getFarmFile( $farmname ) == -1 )
	{
		my $msg = "The farmname $farmname does not exists.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# validate FARM TYPE
	my $type = &getFarmType( $farmname );
	unless ( $type eq 'l4xnat' || $type eq 'datalink' )
	{
		my $msg = "The $type farm profile has backends only in services.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	require Zevenet::Farm::Backend;

	my @backends     = &getFarmServers( $farmname );
	my $backend_line = $backends[$id_server];

	if ( !$backend_line )
	{
		my $msg = "Could not find a backend with such id.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my $status = &runFarmServerDelete( $id_server, $farmname );

	if ( $status == -1 )
	{
		my $msg =
		  "It's not possible to delete the backend with ID $id_server of the $farmname farm.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	&zenlog(
		   "ZAPI success, the backend $id_server in farm $farmname has been deleted." );

	if ( eval { require Zevenet::Cluster; } )
	{
		&runZClusterRemoteManager( 'farm', 'restart', $farmname );
	}

	my $message = "Backend removed";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $message,
				 status      => &getFarmVipStatus( $farmname ),
	};

	&httpResponse( { code => 200, body => $body } );
}

#  DELETE /farms/<farmname>/services/<servicename>/backends/<backendid> Delete a backend of a Service
sub delete_service_backend    # ( $farmname, $service, $id_server )
{
	my ( $farmname, $service, $id_server ) = @_;

	my $desc = "Delete service backend";

	# validate FARM NAME
	if ( &getFarmFile( $farmname ) == -1 )
	{
		my $msg = "The farmname $farmname does not exists.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# validate FARM TYPE
	my $type = &getFarmType( $farmname );

	if ( $type eq 'gslb' )
	{
		require Zevenet::ELoad;
		&eload(
				module => 'Zevenet::API31::Farm::GSLB',
				func   => 'delete_gslb_service_backend',
				args   => [$farmname, $service, $id_server]
		);
	}
	elsif ( $type !~ /^https?$/ )
	{
		my $msg = "The $type farm profile does not support services.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	# HTTP
	require Zevenet::Farm::Base;
	require Zevenet::Farm::Action;
	require Zevenet::Farm::HTTP::Config;
	require Zevenet::Farm::HTTP::Backend;
	require Zevenet::Farm::HTTP::Service;

	# validate SERVICE
	my @services = &getHTTPFarmServices( $farmname );

	# check if the SERVICE exists
	unless ( grep { $service eq $_ } @services )
	{
		my $msg = "Could not find the requested service.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	my @backends =
	  split ( "\n", &getHTTPFarmVS( $farmname, $service, "backends" ) );
	my $be_found = grep { ( split ( " ", $_ ) )[1] == $id_server } @backends;

	# check if the backend id is available
	unless ( $be_found )
	{
		my $msg = "Could not find the requested backend.";
		&httpErrorResponse( code => 400, desc => $desc, msg => $msg );
	}

	my $status = &runHTTPFarmServerDelete( $id_server, $farmname, $service );

	# check if there was an error deleting the backend
	if ( $status == -1 )
	{
		&zenlog( "It's not possible to delete the backend." );

		my $msg =
		  "Could not find the backend with ID $id_server of the $farmname farm.";
		&httpErrorResponse( code => 404, desc => $desc, msg => $msg );
	}

	# no error found, return successful response
	&zenlog(
		"ZAPI success, the backend $id_server in service $service in farm $farmname has been deleted."
	);

	if ( &getFarmStatus( $farmname ) eq 'up' )
	{
		&setFarmRestart( $farmname );
	}

	my $message = "Backend removed";
	my $body = {
				 description => $desc,
				 success     => "true",
				 message     => $message,
				 status      => &getFarmVipStatus( $farmname ),
	};

	&httpResponse( { code => 200, body => $body } );
}

1;
