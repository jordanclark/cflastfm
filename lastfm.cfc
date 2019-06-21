component {

	function init(
		required string apiKey
	,	required string secretKey
	,	required string apiUrl= "http://ws.audioscrobbler.com/2.0/"
	,	numeric throttle= 200
	,	numeric httpTimeOut= 60
	,	boolean debug= ( request.debug ?: false )
	) {
		this.apiKey= arguments.apiKey;
		this.secretKey= arguments.secretKey;
		this.apiUrl= arguments.apiUrl;
		this.httpTimeOut= arguments.httpTimeOut;
		this.throttle= arguments.throttle;
		this.debug= arguments.debug;
		this.lastRequest= server.lastfm_lastRequest ?: 0;
		return this;
	}

	function debugLog( required input ) {
		if ( structKeyExists( request, "log" ) && isCustomFunction( request.log ) ) {
			if ( isSimpleValue( arguments.input ) ) {
				request.log( "LastFM: " & arguments.input );
			} else {
				request.log( "LastFM: (complex type)" );
				request.log( arguments.input );
			}
		} else if( this.debug ) {
			cftrace( text=( isSimpleValue( arguments.input ) ? arguments.input : "" ), var=arguments.input, category="LastFM", type="information" );
		}
		return;
	}

	struct function apiRequest( required string apiMethod ) {
		var http= {};
		var dataKeys= 0;
		var item= "";
		var out= {
			success= false
		,	error= ""
		,	status= ""
		,	statusCode= 0
		,	response= ""
		,	requestUrl= this.apiUrl
		};
		arguments[ "format" ]= "json";
		arguments[ "api_key" ]= this.apiKey;
		arguments[ "method" ]= arguments.apiMethod;
		structDelete( arguments, "apiMethod" );
		out.requestUrl &= this.structToQueryString( arguments );
		this.debugLog( out.requestUrl );
		// throttle requests by sleeping the thread to prevent overloading api
		if ( this.lastRequest > 0 && this.throttle > 0 ) {
			var wait= this.throttle - ( getTickCount() - this.lastRequest );
			if ( wait > 0 ) {
				this.debugLog( "Pausing for #wait#/ms" );
				sleep( wait );
			}
		}
		cftimer( type="debug", label="lastfm request" ) {
			cfhttp( result="http", method="GET", url=out.requestUrl, charset="UTF-8", throwOnError=false, timeOut=this.httpTimeOut );
			if ( this.throttle > 0 ) {
				this.lastRequest= getTickCount();
				server.lastfm_lastRequest= this.lastRequest;
			}
		}
		out.response= toString( http.fileContent );
		// this.debugLog( http );
		// this.debugLog( out.response );
		out.statusCode = http.responseHeader.Status_Code ?: 500;
		this.debugLog( out.statusCode );
		if ( left( out.statusCode, 1 ) == 4 || left( out.statusCode, 1 ) == 5 ) {
			out.success= false;
			out.error= "status code error: #out.statusCode#";
		} else if ( out.response == "Connection Timeout" || out.response == "Connection Failure" ) {
			out.error= out.response;
		} else if ( left( out.statusCode, 1 ) == 2 ) {
			out.success= true;
		}
		// parse response 
		if ( len( out.response ) ) {
			try {
				out.json= deserializeJSON( out.response );
				if ( isStruct( out.json ) && structKeyExists( out.json, "status" ) && out.json.status == "error" ) {
					out.success= false;
					out.error= out.json.message;
				}
				if ( structCount( out.json ) == 1 ) {
					out.json= out.json[ structKeyList( out.json ) ];
				}
			} catch (any cfcatch) {
				out.error= "JSON Error: " & (cfcatch.message?:"No catch message") & " " & (cfcatch.detail?:"No catch detail");
			}
		}
		if ( len( out.error ) ) {
			out.success= false;
		}
		return out;
	}

	/**
	 * http://www.last.fm/api/show/chart.topTags
	 */
	struct function topTags( numeric limit= 50, numeric page= 1 ) {
		var args= {
			"limit"= arguments.limit
		,	"page"= arguments.page
		};
		var out= this.apiRequest(
			apiMethod= "chart.topTags"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/geo.getTopTracks OR http://www.last.fm/api/show/chart.getTopTracks
	 */
	struct function topTracks( string country= "", string location= "", numeric limit= 50, numeric page= 1 ) {
		var args= {
			"limit"= arguments.limit
		,	"page"= arguments.page
		};
		if ( len( arguments.country ) ) {
			args[ "country" ]= lCase( arguments.country );
		}
		if ( len( arguments.location ) ) {
			args[ "location" ]= arguments.location;
		}
		var out= this.apiRequest(
			apiMethod= ( len( arguments.country ) ? "geo.getTopTracks" : "chart.getTopTracks" )
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/chart.getTopArtists OR http://www.last.fm/api/show/chart.getTopArtists
	 */
	struct function topArtists( string country= "", numeric limit= 50, numeric page= 1 ) {
		var args= {
			"limit"= arguments.limit
		,	"page"= arguments.page
		};
		if ( len( arguments.country ) ) {
			args[ "country" ]= arguments.country;
		}
		var out= this.apiRequest(
			apiMethod= ( len( arguments.country ) ? "geo.getTopArtists" : "chart.getTopArtists" )
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/artist.getCorrection
	 */
	struct function artistCorrection( required string artist ) {
		var args= {
			"artist"= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" )
		};
		var out= this.apiRequest(
			apiMethod= "artist.getCorrection"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/artist.getInfo
	 */
	struct function artistInfo( required string artist, string lang= "en", boolean autocorrect= false, string username= "" ) {
		var args= {
			"autocorrect"= ( arguments.autocorrect ? 1 : 0 )
		,	"lang"= lCase( arguments.lang )
		};
		if ( len( arguments.username ) ) {
			args[ "username" ]= arguments.username;
		}
		if ( len( arguments.artist ) == 36 && listLen( arguments.artist, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.artist;
		} else {
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
		}
		var out= this.apiRequest(
			apiMethod= "artist.getInfo"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/artist.getSimilar
	 */
	struct function artistSimilar( required string artist, numeric limit= 50, boolean autocorrect= false ) {
		var args= {
			"limit"= arguments.limit
		,	"autocorrect"= ( arguments.autocorrect ? 1 : 0 )
		};
		if ( len( arguments.artist ) == 36 && listLen( arguments.artist, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.artist;
		} else {
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
		}
		var out= this.apiRequest(
			apiMethod= "artist.getSimilar"
		,	argumentCollection= args
		);
		out.similar= [];
		if ( out.success && structKeyExists( out.json, "artist" ) && isArray( out.json.artist ) ) {
			out.similar= out.json.artist;
		}
		return out;
	}

	/**
	 * http://www.last.fm/api/show/artist.getTags
	 */
	struct function artistTags( required string artist, required string username, boolean autocorrect= false ) {
		var args= {
			"autocorrect"= ( arguments.autocorrect ? 1 : 0 )
		,	"user"= arguments.username
		};
		if ( len( arguments.artist ) == 36 && listLen( arguments.artist, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.artist;
		} else {
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
		}
		var out= this.apiRequest(
			apiMethod= "artist.getTags"
		,	argumentCollection= args
		);
		out.tags= [];
		if ( out.success && structKeyExists( out.json, "tag" ) && isArray( out.json.tag ) ) {
			out.tags= out.json.tag;
		}
		return out;
	}

	/**
	 * http://www.last.fm/api/show/artist.getTopAlbums
	 */
	struct function artistTopAlbums( required string artist, numeric page= 1, numeric limit= 50, boolean autocorrect= false ) {
		var args= {
			"page"= arguments.page
		,	"limit"= arguments.limit
		,	"autocorrect"= ( arguments.autocorrect ? 1 : 0 )
		};
		if ( len( arguments.artist ) == 36 && listLen( arguments.artist, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.artist;
		} else {
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
		}
		var out= this.apiRequest(
			apiMethod= "artist.getTopAlbums"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/artist.getTopTags
	 */
	struct function artistTopTags( required string artist, boolean autocorrect= false ) {
		var args= {
			"autocorrect"= ( arguments.autocorrect ? 1 : 0 )
		};
		if ( len( arguments.artist ) == 36 && listLen( arguments.artist, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.artist;
		} else {
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
		}
		var out= this.apiRequest(
			apiMethod= "artist.getTopTags"
		,	argumentCollection= args
		);
		out.tags= [];
		if ( out.success && structKeyExists( out.json, "tag" ) && isArray( out.json.tag ) ) {
			out.tags= out.json.tag;
		}
		return out;
	}

	/**
	 * http://www.last.fm/api/show/artist.getTopTracks
	 */
	struct function artistTopTracks( required string artist, numeric page= 1, numeric limit= 50, boolean autocorrect= false, string order= "popularity" ) {
		var args= {
			"page"= arguments.page
		,	"limit"= arguments.limit
		,	"autocorrect"= ( arguments.autocorrect ? 1 : 0 )
		};
		if ( len( arguments.artist ) == 36 && listLen( arguments.artist, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.artist;
		} else {
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
		}
		var out= this.apiRequest(
			apiMethod= "artist.getTopTracks"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/artist.search
	 */
	struct function artistSearch( required string artist, numeric page= 1, numeric limit= 50 ) {
		var args= {
			"artist"= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" )
		,	"page"= arguments.page
		,	"limit"= arguments.limit
		};
		var out= this.apiRequest(
			apiMethod= "artist.search"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/track.getCorrection
	 */
	struct function trackCorrection( string artist= "", required string track ) {
		var args= {
			"artist"= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" )
		,	"track"= arguments.track
		};
		var out= this.apiRequest(
			apiMethod= "track.getInfo"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/track.getInfo
	 */
	struct function trackInfo( required string track, string artist= "", string username= "", boolean autocorrect= false ) {
		var args= {};
		if ( len( arguments.track ) == 36 && listLen( arguments.track, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.track;
		} else {
			args[ "track" ]= arguments.track;
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
			args[ "autocorrect" ]= ( arguments.autocorrect ? 1 : 0 );
		}
		if ( len( arguments.username ) ) {
			args[ "username" ]= arguments.username;
		}
		var out= this.apiRequest(
			apiMethod= "track.getInfo"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/track.getSimilar
	 */
	struct function trackSimilar( required string track, string artist= "", boolean autocorrect= false, numeric limit= 50 ) {
		var args= {
			"limit"= arguments.limit
		};
		if ( len( arguments.track ) == 36 && listLen( arguments.track, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.track;
		} else {
			args[ "track" ]= arguments.track;
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
			args[ "autocorrect" ]= ( arguments.autocorrect ? 1 : 0 );
		}
		var out= this.apiRequest(
			apiMethod= "track.getSimilar"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/track.getTags
	 */
	struct function trackTags( required string track, string artist= "", boolean autocorrect= false, string username= "" ) {
		var args= {};
		if ( len( arguments.track ) == 36 && listLen( arguments.track, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.track;
		} else {
			args[ "track" ]= arguments.track;
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
			args[ "autocorrect" ]= ( arguments.autocorrect ? 1 : 0 );
		}
		if ( len( arguments.username ) ) {
			args[ "user" ]= arguments.username;
		}
		var out= this.apiRequest(
			apiMethod= "track.getTags"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/track.getTopTags
	 */
	struct function trackTopTags( required string track, string artist= "", boolean autocorrect= false ) {
		var args= {};
		if ( len( arguments.track ) == 36 && listLen( arguments.track, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.track;
		} else {
			args[ "track" ]= arguments.track;
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
			args[ "autocorrect" ]= ( arguments.autocorrect ? 1 : 0 );
		}
		if ( len( arguments.username ) ) {
			args[ "user" ]= arguments.username;
		}
		var out= this.apiRequest(
			apiMethod= "track.getTopTags"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/track.search
	 */
	struct function trackSearch( required string track, string artist= "", numeric page= 1, numeric limit= 30 ) {
		var args= {
			"artist"= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" )
		,	"track"= arguments.track
		,	"page"= arguments.page
		,	"limit"= arguments.limit
		};
		var out= this.apiRequest(
			apiMethod= "track.search"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/album.getInfo
	 */
	struct function albumInfo( required string album, required string artist, string lang= "en", boolean autocorrect= false, string username= "" ) {
		var args= {
			"lang"= lCase( arguments.lang )
		};
		if ( len( arguments.album ) == 36 && listLen( arguments.album, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.album;
		} else {
			args[ "album" ]= arguments.album;
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
			args[ "autocorrect" ]= ( arguments.autocorrect ? 1 : 0 );
		}
		if ( len( arguments.username ) ) {
			args[ "username" ]= arguments.username;
		}
		var out= this.apiRequest(
			apiMethod= "album.albumInfo"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/album.getTags
	 */
	struct function albumTags( required string album, required string artist, string lang= "en", boolean autocorrect= false, string username= "" ) {
		var args= {
			"lang"= lCase( arguments.lang )
		};
		if ( len( arguments.album ) == 36 && listLen( arguments.album, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.album;
		} else {
			args[ "album" ]= arguments.album;
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
			args[ "autocorrect" ]= ( arguments.autocorrect ? 1 : 0 );
		}
		if ( len( arguments.username ) ) {
			args[ "user" ]= arguments.username;
		}
		var out= this.apiRequest(
			apiMethod= "album.getTags"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/album.getTags
	 */
	struct function albumTopTags( required string album, required string artist, string lang= "en", boolean autocorrect= false ) {
		var args= {
			"lang"= lCase( arguments.lang )
		};
		if ( len( arguments.album ) == 36 && listLen( arguments.album, "-" ) == 5 ) {
			args[ "mbid" ]= arguments.album;
		} else {
			args[ "album" ]= arguments.album;
			args[ "artist" ]= replace( replace( arguments.artist, "&", "and", "all" ), "/", "", "all" );
			args[ "autocorrect" ]= ( arguments.autocorrect ? 1 : 0 );
		}
		var out= this.apiRequest(
			apiMethod= "album.getTopTags"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/album.search
	 */
	struct function albumSearch( required string album, numeric page= 1, numeric limit= 30 ) {
		var args= {
			"album"= arguments.album
		,	"page"= arguments.page
		,	"limit"= arguments.limit
		};
		var out= this.apiRequest(
			apiMethod= "album.search"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/tag.getInfo
	 */
	struct function tagInfo( required string tag, string lang= "en" ) {
		var args= {
			"tag"= arguments.tag
		,	"lang"= lCase( arguments.lang )
		};
		var out= this.apiRequest(
			apiMethod= "tag.getInfo"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/tag.getSimilar
	 */
	struct function tagSimilar( required string tag ) {
		var args= {
			"tag"= arguments.tag
		};
		var out= this.apiRequest(
			apiMethod= "tag.getSimilar"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/tag.getTopAlbums
	 */
	struct function tagTopAlbums( required string tag, numeric page= 1, numeric limit= 50 ) {
		var args= {
			"tag"= arguments.tag
		,	"page"= arguments.page
		,	"limit"= arguments.limit
		};
		var out= this.apiRequest(
			apiMethod= "tag.getTopAlbums"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/tag.getTopArtists
	 */
	struct function tagTopArtists( required string tag, numeric page= 1, numeric limit= 50 ) {
		var args= {
			"tag"= arguments.tag
		,	"page"= arguments.page
		,	"limit"= arguments.limit
		};
		var out= this.apiRequest(
			apiMethod= "tag.getTopArtists"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/tag.getTopTracks
	 */
	struct function tagTopTracks( required string tag, numeric page= 1, numeric limit= 50 ) {
		var args= {
			"tag"= arguments.tag
		,	"page"= arguments.page
		,	"limit"= arguments.limit
		};
		var out= this.apiRequest(
			apiMethod= "tag.getTopTracks"
		,	argumentCollection= args
		);
		return out;
	}

	/**
	 * http://www.last.fm/api/show/tag.getTopArtists
	 */
	struct function tagArtists( required string tag, numeric page= 1, numeric limit= 50 ) {
		var args= {
			"tag"= arguments.tag
		,	"page"= arguments.page
		,	"limit"= arguments.limit
		};
		var out= this.this.apiRequest(
			apiMethod= "tag.topArtists"
		,	argumentCollection= args
		);
		return out;
	}

	string function structToQueryString( required struct stInput, boolean bEncode= true, string lExclude= "", string sDelims= "," ) {
		var sOutput= "";
		var sItem= "";
		var sValue= "";
		var amp= "?";
		for ( sItem in stInput ) {
			if ( !len( lExclude ) || !listFindNoCase( lExclude, sItem, sDelims ) ) {
				try {
					sValue= stInput[ sItem ];
					if ( len( sValue ) ) {
						if ( bEncode ) {
							sOutput &= amp & lCase( sItem ) & "=" & urlEncodedFormat( sValue );
						} else {
							sOutput &= amp & lCase( sItem ) & "=" & sValue;
						}
						amp= "&";
					}
				} catch (any cfcatch) {
				}
			}
		}
		return sOutput;
	}

}
