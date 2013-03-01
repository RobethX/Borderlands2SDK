#ifndef EXCEPTIONS_H
#define EXCEPTIONS_H

#include <string>
#include <stdexcpt.h>

class FatalSDKException : public std::runtime_error
{
private:
	int m_errorCode;

public:
	FatalSDKException(int errorCode, const char* errorStr)
		: std::runtime_error(errorStr),
		m_errorCode(errorCode)
	{
	}
};

#endif