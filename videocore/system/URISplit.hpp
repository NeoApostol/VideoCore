//
//  URISplit.hpp
//  unnamed-cpp
//
//  Created by Alexey Shtanko on 2/13/17.
//  Copyright © 2017 Alexey Shtanko. All rights reserved.
//

#ifndef URISplit_hpp
#define URISplit_hpp

#include <stdio.h>
#include <iostream>
#include <sstream>
#include <vector>
#include <videocore/system/UriParser.hpp>

class URISplit {

	inline std::string trim(const std::string &s)
	{
		auto wsfront=std::find_if_not(s.begin(),s.end(),[](int c){return std::isspace(c);});
		auto wsback=std::find_if_not(s.rbegin(),s.rend(),[](int c){return std::isspace(c);}).base();
		return (wsback<=wsfront ? std::string() : std::string(wsfront,wsback));
	}

	template <typename OutputIter>
    void Str2Arr( const std::string &str, const std::string &delim, int start, bool ignoreEmpty, OutputIter iter )
	{
		int pos = str.find_first_of( delim, start );
		if (pos != std::string::npos) {
			std::string nStr = str.substr( start, pos - start );
			trim( nStr );

			if (!nStr.empty() || !ignoreEmpty)
				*iter++ = nStr;
			Str2Arr( str, delim, pos + 1, ignoreEmpty, iter );
		}
		else
		{
			std::string nStr = str.substr( start, str.length() - start );
			trim( nStr );

			if (!nStr.empty() || !ignoreEmpty)
				*iter++ = nStr;
		}
	}

	public: std::vector<std::string> Str2Arr( const std::string &str, const std::string &delim )
	{
		std::vector<std::string> result;
		Str2Arr( str, delim, 0, true, std::back_inserter( result ) );
		return std::move( result );
	}


public:
	http::url                       m_uri, s_uri;
	std::string                     m_app, s_app;
	std::string                     m_playPath, s_playPath;
};

#endif /* URISplit_hpp */
