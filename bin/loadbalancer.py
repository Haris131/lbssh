#!/usr/bin/python
#
# PumpkinLB Copyright (c) 2014-2015, 2017 Tim Savannah under GPLv3.
# You should have received a copy of the license as LICENSE 
#
# See: https://github.com/kata198/PumpkinLB

import math
import multiprocessing
import os
import platform
import socket
import sys
import signal
import threading
import traceback
import time
import random
import select
from datetime import datetime
try:
    from ConfigParser import ConfigParser
except:
    from configparser import ConfigParser

### version ###
pumpkinlb_version = '2.0.0'

### constants ###
GRACEFUL_SHUTDOWN_TIME = 6
DEFAULT_BUFFER_SIZE = 4096


### log ###
def logit(fileObj, msg):
    fileObj.write("[ %s ] %s" %(datetime.now().ctime(), msg))
    if msg[-1] != '\n':
        fileObj.write('\n')
    fileObj.flush()

def logmsg(msg):
    logit(sys.stdout, msg)

def logerr(msg):
    logit(sys.stderr, msg)


### usage ###
def printUsage(toStream=sys.stdout):
    toStream.write('''Usage: %s [config file]
Starts Pumpkin Load Balancer using the given config file.

  Arguments:

    --help                         Print this message
    --help-config                  Print help regarding usage of the config file
    --version                      Show version information

  Signals:

    SIGTERM                        Performs a graceful shutdown

%s
''' %(os.path.basename(sys.argv[0]), getVersionStr())
    )
#    SIGUSR1                        Re-read the config, and alter service to match TODO: NOT DONE

def printConfigHelp(toStream=sys.stdout):
    toStream.write('''Config Help

Config file is broken up into sections, definable by [$SectionName], followed by variables in format of key=value.

  Sections:

    [options]
      pre_resolve_workers=0/1                     [Default 1]    Any workers defined with a hostname will be evaluated at the time the config is read. 
                                                                   This is preferable as it saves a DNS trip for every request, and should be enabled
                                                                   unless your DNS is likely to change and you want the workers to match the change.

      buffer_size=N                             [Default %d]   Default read/write buffer size (in bytes) used on socket operations. 4096 is a good default for most, but you may be able to tune better depending on your application.

    [mappings]
      localaddr:inport=worker1:port,worker2:port...              Listen on interface defined by "localaddr" on port "inport". Farm out to worker addresses and ports. Ex: 192.168.1.100:80=10.10.0.1:5900,10.10.0.2:5900
        or
      inport=worker1:port,worker2:port...                        Listen on all interfaces on port "inport", and farm out to worker addresses with given ports. Ex: 80=10.10.0.1:5900,10.10.0.2:5900

''' %(DEFAULT_BUFFER_SIZE, )
    )

def getVersionStr():
    return 'PumpkinLB Version %s (c) 2014-2015 Timothy Savannah GPLv3' %(pumpkinlb_version,)


### config ###
class PumpkinMapping(object):
    '''
        Represents a mapping of a local listen to a series of workers
    '''
    def __init__(self, localAddr, localPort, workers):
        self.localAddr = localAddr or ''
        self.localPort = int(localPort)
        self.workers = workers

    def getListenerArgs(self):
        return [self.localAddr, self.localPort, self.workers]

    def addWorker(self, workerAddr, workerPort):
        self.workers.append( {'port' : int(workerPort), 'addr' : workerAddr} )

    def removeWorker(self, workerAddr, workerPort):
        newWorkers = []
        workerPort = int(workerPort)
        removedWorker = None
        for worker in self.workers:
            if worker['addr'] == workerAddr and worker['port'] == workerPort:
                removedWorker = worker
                continue
            newWorkers.append(worker)
        self.workers = newWorkers
        return removedWorker

class PumpkinConfig(ConfigParser):
    '''
        The class for managing Pumpkin's Config File
    '''
    def __init__(self, configFilename):
        ConfigParser.__init__(self)
        self.configFilename = configFilename

        self._options = {
            'pre_resolve_workers' : True,
            'buffer_size'         : DEFAULT_BUFFER_SIZE,
        }
        self._mappings = {}

    def parse(self):
        '''
            Parse the config file
        '''
        try:
            f = open(self.configFilename, 'rt')
        except IOError as e:
            logerr('Could not open config file: "%s": %s\n' %(self.configFilename, str(e)))
            raise e
        [self.remove_section(s) for s in self.sections()]
        self.read_file(f)
        f.close()

        self._processOptions()
        self._processMappings()

    def getOptions(self):
        '''
            Gets the options dictionary
        '''
        return self._options

    def getOptionValue(self, optionName):
        '''
            getOptionValue - Gets the value of an option
        '''
        return self._options[optionName]

    def getMappings(self):
        '''
            Gets the mappings dictionary
        '''
        return self._mappings

    def _processOptions(self):
        # I personally think the config parser interface sucks...
        if 'options' not in self._sections:
            return

        try:
            preResolveWorkers = self.get('options', 'pre_resolve_workers')
            if preResolveWorkers == '1' or preResolveWorkers.lower() == 'true':
                self._options['pre_resolve_workers'] = True
            elif preResolveWorkers == '0' or preResolveWorkers.lower() == 'false':
                self._options['pre_resolve_workers'] = False
            else:
                logerr('WARNING: Unknown value for [options] -> pre_resolve_workers "%s" -- ignoring value, retaining previous "%s"\n' %(str(preResolveWorkers), str(self._options['pre_resolve_workers'])) )
        except:
            pass

        try:
            bufferSize = self.get('options', 'buffer_size')
            if bufferSize.isdigit() and int(bufferSize) > 0:
                self._options['buffer_size'] = int(bufferSize)
            else:
                logerr('WARNING: buffer_size must be an integer > 0 (bytes). Got "%s" -- ignoring value, retaining previous "%s"\n' %(bufferSize, str(self._options['buffer_size'])) )
        except Exception as e:
            logerr('Error parsing [options]->buffer_size : %s. Retaining default, %s\n' %(str(e),str(DEFAULT_BUFFER_SIZE)) )

    def _processMappings(self):

        if 'mappings' not in self._sections:
            raise PumpkinConfigException('ERROR: Config is missing required "mappings" section.\n')

        preResolveWorkers = self._options['pre_resolve_workers']

        mappings = {}
        mappingSectionItems = self.items('mappings')
        
        for (addrPort, workers) in mappingSectionItems:
            addrPortSplit = addrPort.split(':')
            addrPortSplitLen = len(addrPortSplit)
            if not workers:
                logerr('WARNING: Skipping, no workers defined for %s\n' %(addrPort,))
                continue
            if addrPortSplitLen == 1:
                (localAddr, localPort) = ('0.0.0.0', addrPort)
            elif addrPortSplitLen == 2:
                (localAddr, localPort) = addrPortSplit
            else:
                logerr('WARNING: Skipping Invalid mapping: %s=%s\n' %(addrPort, workers))
                continue
            try:
                localPort = int(localPort)
            except ValueError:
                logerr('WARNING: Skipping Invalid mapping, cannot convert port: %s\n' %(addrPort,))
                continue

            workerLst = []
            for worker in workers.split(','):
                workerSplit = worker.split(':')
                if len(workerSplit) != 2 or len(workerSplit[0]) < 3 or len(workerSplit[1]) == 0:
                    logerr('WARNING: Skipping Invalid Worker %s\n' %(worker,))

                if preResolveWorkers is True:
                    try:
                        addr = socket.gethostbyname(workerSplit[0])
                    except:
                        logerr('WARNING: Skipping Worker, could not resolve %s\n' %(workerSplit[0],))
                else:
                    addr = workerSplit[0]
                try:
                    port = int(workerSplit[1])
                except ValueError:
                    logerr('WARNING: Skipping worker, could not parse port %s\n' %(workerSplit[1],))

                workerLst.append({'addr' : addr, 'port' : port})

            keyName = "%s:%s" %(localAddr, addrPort)
            if keyName in mappings:
                logerr('WARNING: Overriding existing mapping of %s with %s\n' %(addrPort, str(workerLst)))
            mappings[addrPort] = PumpkinMapping(localAddr, localPort, workerLst)

        self._mappings = mappings

class PumpkinConfigException(Exception):
    pass


### listener ###
class PumpkinListener(multiprocessing.Process):
    '''
        Class that listens on a local port and forwards requests to workers
    '''
    def __init__(self, localAddr, localPort, workers, bufferSize=DEFAULT_BUFFER_SIZE):
        multiprocessing.Process.__init__(self)
        self.localAddr = localAddr
        self.localPort = localPort
        self.workers = workers
        self.bufferSize = bufferSize
        self.activeWorkers = []   # Workers currently processing a job
        self.listenSocket = None  # Socket for incoming connections
        self.cleanupThread = None # Cleans up completed workers
        self.keepGoing = True     # Flips to False when the application is set to terminate

    def cleanup(self):
        time.sleep(2) # Wait for things to kick off
        while self.keepGoing is True:
            currentWorkers = self.activeWorkers[:]
            for worker in currentWorkers:
                worker.join(.02)
                if worker.is_alive() == False: # Completed
                    self.activeWorkers.remove(worker)
            time.sleep(1.5)

    def closeWorkers(self, *args):
        self.keepGoing = False
        time.sleep(1)

        try:
            self.listenSocket.shutdown(socket.SHUT_RDWR)
        except:
            pass
        try:
            self.listenSocket.close()
        except:
            pass

        if not self.activeWorkers:
            self.cleanupThread and self.cleanupThread.join(3)
            signal.signal(signal.SIGTERM, signal.SIG_DFL)
            sys.exit(0)

        for pumpkinWorker in self.activeWorkers:
            try:
                pumpkinWorker.terminate()
                os.kill(pumpkinWorker.pid, signal.SIGTERM)
            except:
                pass

        time.sleep(1)

        remainingWorkers = []
        for pumpkinWorker in self.activeWorkers:
            pumpkinWorker.join(.03)
            if pumpkinWorker.is_alive() is True: # Still running
                remainingWorkers.append(pumpkinWorker)

        if len(remainingWorkers) > 0:
            # One last chance to complete, then we kill
            time.sleep(1)
            for pumpkinWorker in remainingWorkers:
                pumpkinWorker.join(.2)

        self.cleanupThread and self.cleanupThread.join(2)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        sys.exit(0)

    def retryFailedWorkers(self, *args):
        '''
            retryFailedWorkers - 

                This function loops over current running workers and scans them for a multiprocess shared field called "failedToConnect".
                  If this is set to 1, then we failed to connect to the backend worker. If that happens, we pick a different worker from the pool at random,
                  and assign the client to that new worker.
        '''
        time.sleep(2)
        successfulRuns = 0 # We use this to differ between long waits in between successful periods and short waits when there is a failing host in the mix.
        while self.keepGoing is True:
            currentWorkers = self.activeWorkers[:]
            for worker in currentWorkers:
                if worker.failedToConnect.value == 1:
                    successfulRuns = -1 # Reset the "roll" of successful runs so we start doing shorter sleeps
                    logmsg('Found a failure to connect to worker\n')
                    numWorkers = len(self.workers)
                    if numWorkers > 1:
                        nextWorkerInfo = None
                        while (nextWorkerInfo is None) or (worker.workerAddr == nextWorkerInfo['addr'] and worker.workerPort == nextWorkerInfo['port']):
                            nextWorkerInfo = self.workers[random.randint(0, numWorkers-1)]
                    else:
                        # In this case, we have no option but to try on the same host.
                        nextWorkerInfo = self.workers[0]

                    logmsg('Retrying request from %s from %s:%d on %s:%d\n' %(worker.clientAddr, worker.workerAddr, worker.workerPort, nextWorkerInfo['addr'], nextWorkerInfo['port']))

                    nextWorker = PumpkinWorker(worker.clientSocket, worker.clientAddr, nextWorkerInfo['addr'], nextWorkerInfo['port'], self.bufferSize)
                    nextWorker.start()
                    self.activeWorkers.append(nextWorker)
                    worker.failedToConnect.value = 0 # Clean now
            successfulRuns += 1
            if successfulRuns > 1000000: # Make sure we don't overrun
                successfulRuns = 6
            if successfulRuns > 5:
                time.sleep(2)
            else:
                time.sleep(.05)

    def run(self):
        signal.signal(signal.SIGTERM, self.closeWorkers)

        while True:
            try:
                listenSocket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

                # If on UNIX, bind to port even if connections are still in TIME_WAIT state
                #  (from previous connections, which don't ever be served...)
                # Happens when PumpkinLB Restarts.
                try:
                    listenSocket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                except:
                    pass
                listenSocket.bind( (self.localAddr, self.localPort) )
                self.listenSocket = listenSocket
                break
            except Exception as e:
                logerr('Failed to bind to %s:%d. "%s" Retrying in 5 seconds.\n' %(self.localAddr, self.localPort, str(e)))
                time.sleep(5)

        listenSocket.listen(5)

        # Create thread that will cleanup completed tasks
        self.cleanupThread = cleanupThread = threading.Thread(target=self.cleanup)
        cleanupThread.start()

        # Create thread that will retry failed tasks
        retryThread = threading.Thread(target=self.retryFailedWorkers)
        retryThread.start()

        try:
            while self.keepGoing is True:
                for workerInfo in self.workers:
                    if self.keepGoing is False:
                        break
                    try:
                        (clientConnection, clientAddr) = listenSocket.accept()
                    except:
                        logerr('Cannot bind to %s:%s\n' %(self.localAddr, self.localPort))
                        if self.keepGoing is True:
                            # Exception did not come from termination process, so keep rollin'
                            time.sleep(3)
                            continue
                        
                        raise # Termination DID come from termination process, so abort.

                    worker = PumpkinWorker(clientConnection, clientAddr, workerInfo['addr'], workerInfo['port'], self.bufferSize)
                    self.activeWorkers.append(worker)
                    worker.start()
        except Exception as e:
            logerr('Got exception: %s, shutting down workers on %s:%d\n' %(str(e), self.localAddr, self.localPort))
            self.closeWorkers()
            return

        self.closeWorkers()


### worker ###
class PumpkinWorker(multiprocessing.Process):
    '''
        A class which handles the worker-side of processing a request (communicating between the back-end worker and the requesting client)
    '''
    def __init__(self, clientSocket, clientAddr, workerAddr, workerPort, bufferSize=DEFAULT_BUFFER_SIZE):
        multiprocessing.Process.__init__(self)
        self.clientSocket = clientSocket
        self.clientAddr = clientAddr
        self.workerAddr = workerAddr
        self.workerPort = workerPort
        self.workerSocket = None
        self.bufferSize = bufferSize
        self.failedToConnect = multiprocessing.Value('i', 0)

    def closeConnections(self):
        try:
            self.workerSocket.shutdown(socket.SHUT_RDWR)
        except:
            pass
        try:
            self.workerSocket.close()
        except:
            pass
        try:
            self.clientSocket.shutdown(socket.SHUT_RDWR)
        except:
            pass
        try:
            self.clientSocket.close()
        except:
            pass
        signal.signal(signal.SIGTERM, signal.SIG_DFL)

    def closeConnectionsAndExit(self, *args):
        self.closeConnections()
        sys.exit(0)

    def run(self):
        workerSocket = self.workerSocket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        clientSocket = self.clientSocket

        bufferSize = self.bufferSize

        try:
            workerSocket.connect( (self.workerAddr, self.workerPort) )
        except:
            logerr('Could not connect to worker %s:%d\n' %(self.workerAddr, self.workerPort))
            self.failedToConnect.value = 1
            time.sleep(GRACEFUL_SHUTDOWN_TIME) # Give a few seconds for the "fail" reader to pick this guy up before we are removed by the joining thread
            return

        signal.signal(signal.SIGTERM, self.closeConnectionsAndExit)

        try:
            dataToClient = b''
            dataFromClient = b''
            while True:
                waitingToWrite = []

                if dataToClient:
                    waitingToWrite.append(clientSocket)
                if dataFromClient:
                    waitingToWrite.append(workerSocket)

                try:
                    (hasDataForRead, readyForWrite, hasError) = select.select( [clientSocket, workerSocket], waitingToWrite, [clientSocket, workerSocket], .3)
                except KeyboardInterrupt:
                    break

                if hasError:
                    break
            
                if clientSocket in hasDataForRead:
                    nextData = clientSocket.recv(bufferSize)
                    if not nextData:
                        break
                    dataFromClient += nextData

                if workerSocket in hasDataForRead:
                    nextData = workerSocket.recv(bufferSize)
                    if not nextData:
                        break
                    dataToClient += nextData
            
                if workerSocket in readyForWrite:
                    while dataFromClient:
                        workerSocket.send(dataFromClient[:bufferSize])
                        dataFromClient = dataFromClient[bufferSize:]

                if clientSocket in readyForWrite:
                    while dataToClient:
                        clientSocket.send(dataToClient[:bufferSize])
                        dataToClient = dataToClient[bufferSize:]

        except Exception as e:
            logerr('Error on %s:%d: %s\n' %(self.workerAddr, self.workerPort, str(e)))

        self.closeConnectionsAndExit()


### load balancer ###
if __name__ == '__main__':
    configFilename = None
    for arg in sys.argv[1:]:
        if arg == '--help':
            printUsage(sys.stdout)
            sys.exit(0)
        elif arg == '--help-config':
            printConfigHelp(sys.stdout)
            sys.exit(0)
        elif arg == '--version':
            sys.stdout.write(getVersionStr() + '\n')
            sys.exit(0)
        elif configFilename is not None:
            sys.stderr.write('Too many arguments.\n\n')
            printUsage(sys.stderr)
            sys.exit(0)
        else:
            configFilename = arg

    if not configFilename:
        sys.stderr.write('No config file provided\n\n')
        printUsage(sys.stderr)
        sys.exit(1)

    pumpkinConfig = PumpkinConfig(configFilename)
    try:
        pumpkinConfig.parse()
    except PumpkinConfigException as configError:
        sys.stderr.write(str(configError) + '\n\n\n')
        printConfigHelp()
        sys.exit(1)
    except Exception as e:
        traceback.print_exc(file=sys.stderr)
        printConfigHelp(sys.stderr)
        sys.exit(1)

    bufferSize = pumpkinConfig.getOptionValue('buffer_size')
    logmsg('Configured buffer size = %d bytes\n' %(bufferSize,))

    mappings = pumpkinConfig.getMappings()
    listeners = []
    for mappingAddr, mapping in mappings.items():
        logmsg('Starting up listener on %s:%d with mappings: %s\n' %(mapping.localAddr, mapping.localPort, str(mapping.workers)))
        listener = PumpkinListener(mapping.localAddr, mapping.localPort, mapping.workers, bufferSize)
        listener.start()
        listeners.append(listener)

    globalIsTerminating = False

    def handleSigTerm(*args):
        global listeners
        global globalIsTerminating
#        sys.stderr.write('CALLED\n')
        if globalIsTerminating is True:
            return # Already terminating
        globalIsTerminating = True
        logerr('Caught signal, shutting down listeners...\n')
        for listener in listeners:
            try:
                os.kill(listener.pid, signal.SIGTERM)
            except:
                pass
        logerr('Sent signal to children, waiting up to 4 seconds then trying to clean up\n')
        time.sleep(1)
        startTime = time.time()
        remainingListeners = listeners
        remainingListeners2 = []
        for listener in remainingListeners:
            logerr('Waiting on %d...\n' %(listener.pid,))
            listener.join(.05)
            if listener.is_alive() is True:
                remainingListeners2.append(listener)
        remainingListeners = remainingListeners2
        logerr('Remaining (%d) listeners are: %s\n' %(len(remainingListeners), [listener.pid for listener in remainingListeners]))

        afterJoinTime = time.time()

        if remainingListeners:
            delta = afterJoinTime - startTime
            remainingSleep = int(GRACEFUL_SHUTDOWN_TIME - math.floor(afterJoinTime - startTime))
            if remainingSleep > 0:
                anyAlive = False
                # If we still have time left, see if we are just done or if there are children to clean up using remaining time allotment
                if threading.activeCount() > 1 or len(multiprocessing.active_children()) > 0:
                    logerr('Listener closed in %1.2f seconds. Waiting up to %d seconds before terminating.\n' %(delta, remainingSleep))
                    thisThread = threading.current_thread()
                    for i in range(remainingSleep):
                        allThreads = threading.enumerate()
                        anyAlive = False
                        for thread in allThreads:
                            if thread is thisThread or thread.name == 'MainThread':
                                continue
                            thread.join(.05)
                            if thread.is_alive() == True:
                                anyAlive = True

                        allChildren = multiprocessing.active_children()
                        for child in allChildren:
                            child.join(.05)
                            if child.is_alive() == True:
                                anyAlive = True
                        if anyAlive is False:
                            break
                        time.sleep(1)

                if anyAlive is True:
                    logerr('Could not kill in time.\n')
                else:
                    logerr('Shutdown successful after %1.2f seconds.\n' %( time.time() - startTime))

            else:
                logerr('Listener timed out in closing, exiting uncleanly.\n')
                time.sleep(.05) # Why not? :P

        logmsg('exiting...\n')
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        sys.exit(0)
        os.kill(os.getpid(), signal.SIGTERM)
        return 0
    # END handleSigTerm

    signal.signal(signal.SIGTERM, handleSigTerm)
    signal.signal(signal.SIGINT, handleSigTerm)

    while True:
        try:
            time.sleep(2)
        except:
            os.kill(os.getpid(), signal.SIGTERM)
