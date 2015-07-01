
import io = std.stdio;
import std.socket;
import std.string;
import std.datetime;
import core.thread : Thread;

/// Requests the current thread to sleep for <ms> milliseconds.
private void sleepms(int ms)
{
	Thread.sleep(dur!("msecs")(ms));
}

/// Returns the time in <ms> milliseconds
private SysTime timeInMs(int ms)
{
	return Clock.currTime() + dur!("msecs")(ms);
}

/// Returns true if the current time is past the given time, false otherwise.
private bool pastTime(SysTime time)
{
	return Clock.currTime() > time;
}

// Protocol: https://developer.valvesoftware.com/wiki/Master_Server_Query_Protocol

enum Region
{
	usEastCoast = 0,
	usWestCoast = 1,
	southAmerica = 2,
	europe = 3,
	asia = 4,
	australia = 5,
	middleEast = 6,
	africa = 7,
	
	world = 255,
}

struct Query
{
	Region region;
	string ip;
	string filter;
}


struct IPAddress
{
	union
	{
		ubyte[4] bytes;
		uint integer;
		struct
		{
			ubyte a;
			ubyte b;
			ubyte c;
			ubyte d;
		}
	}
	
	ushort port;
	
	/// Returns the first byte of the address as an integer.
	@property int ai(){ return cast(int)a; }
	/// Returns the second byte of the address as an integer.
	@property int bi(){ return cast(int)b; }
	/// Returns the third byte of the address as an integer.
	@property int ci(){ return cast(int)c; }
	/// Returns the fourth byte of the address as an integer.
	@property int di(){ return cast(int)d; }
	
	/// Returns the port as an integer.
	@property int porti(){ return cast(int)port; }
}


class MasterServerQuery
{
	Socket socket;
	
	ubyte[] currentQueryData;
	
	/// Number of seconds to wait on data before making another attempt
	int timeoutDuration = 3;
	/// Number of attempts made to query the master server before exiting
	int maxAttempts = 4;
	
	/// Buffer for received network data.
	ubyte[2048] buffer;
	/// Slice from buffer that has been written to
	ubyte[] bufferSlice;
	
	void delegate(IPAddress) onReceiveIP;
	
	this()
	{
		auto addr = new InternetAddress("hl2master.steampowered.com", 27011);
		socket = new UdpSocket();
		socket.connect(addr);
		socket.blocking = false;
	}
	
	/// Start's a server query
	void query(Query query)
	{
		// 1 byte message type
		// 1 byte region code
		// n+1 bytes string (append null-terminator)
		// n+1 bytes string (append null-terminator)
		int size = 1+1+(query.ip.length+1)+(query.filter.length+1);
		ubyte[] data = new ubyte[size];
		
		ubyte[] slice = data;
		
		// message type
		slice[0] = 0x31;
		slice = slice[1..$];
		
		// region
		slice[0] = cast(ubyte)query.region;
		slice = slice[1..$];
		
		// ip
		slice[0..query.ip.length] = cast(ubyte[])query.ip;
		slice[query.ip.length] = 0;
		slice = slice[query.ip.length+1..$];
		
		// filter
		slice[0..query.filter.length] = cast(ubyte[])query.filter;
		slice[query.filter.length] = 0;
		slice = slice[query.filter.length+1..$];
		
		currentQueryData = data;
		socket.send(data);
		
		bool success = false;
		for(int i = 0; i < maxAttempts; i++)
		{
			if(wait())
			{
				success = true;
				break;
			}
		}
		
		if(!success)
			throw new Exception("Connection timed out.");
		
		process();
		
	}
	
	/// Waits for a response until time out.
	/// Return's true if a response was received and false if a timeout occurs.
	private bool wait()
	{
		ubyte[6] magic = [0xFF, 0xFF, 0xFF, 0xFF, 0x66, 0x0A];
		
		auto timeout = timeInMs(timeoutDuration*1000);
		while(!pastTime(timeout))
		{
			int bytesRead = socket.receive(buffer);
			if(bytesRead > cast(int)magic.length)
			{
				if(buffer[0..magic.length] == magic)
				{
					bufferSlice = buffer[magic.length..bytesRead];
					return true;
				}
				else
				{
					io.writeln("Magic does not match, ignoring packet (size=", bytesRead, ").");
				}
			}
			else if(bytesRead >= 0)
			{
				io.writeln("Magic does not match, ignoring packet (size=", bytesRead, ").");
			}
			else if(bytesRead == socket.ERROR)
			{
				// From testing, bytesRead returns -1 if there is no data
				// to read (non-blocking) or if the buffer size is too small
				// to contain all the data. Error text did not prove useful
				// and just printed: 'The operation completed successfully.'
				// io.writeln("Socket read error: ", socket.getErrorText());
			}
			sleepms(25);
		}
		
		return false;
	}
	
	void process()
	{
		ubyte[] data = bufferSlice;
		
		IPAddress lastIP;
		while(data.length >= 6)
		{
			IPAddress ip;
			ip.a = data[0];
			ip.b = data[1];
			ip.c = data[2];
			ip.d = data[3];
			ip.port = data[4];
			ip.port <<= 8;
			ip.port += data[5];
			
			data = data[6..$];
			
			lastIP = ip;
			
			if(onReceiveIP)
				onReceiveIP(ip);
		}
		if(data.length > 0)
			io.writeln("Extra data in packet: ", data);
		
		
	}
}

void main()
{
	
	MasterServerQuery msq = new MasterServerQuery();
	Query query;
	query.region = Region.world;
	query.ip = "0.0.0.0:0";
	query.filter = "";
	
	msq.onReceiveIP = delegate void(IPAddress ip)
	{
		io.writeln(ip.a, ".", ip.b, ".", ip.c, ".", ip.d, ":", ip.port);
	};
	
	msq.query(query);
	
}
