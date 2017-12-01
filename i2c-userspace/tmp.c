// https://github.com/ManuelSchneid3r/RaspberryPi/raw/master/sensors/src/tmp.c

#include <stdio.h>
#include <stdlib.h>
#include <linux/i2c-dev.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <getopt.h>
#include <math.h>

void print_usage(char * appname) {
    printf("Usage: %s  [--resolution|-r<0-3>][--faultqueue|-f<0-3>][--oneshot|--nooneshot][--activehigh|--activelow][--interruptmode|--comparatormode][--shutdownmode|--noshutdownmode][--query] <i2c char device> <hex address>\n", appname);
}

void print_help(char * appname) {
  print_usage(appname);
  printf(
      "\n"
      "\t--shutdownmode, --noshutdownmode\n"
      "\t\tThe Shutdown Mode allows the user to save maximum power by shutting down all device circuitry other than the serial interface, which reduces current consumption to typically less than 0.1 μA.\n\n"
      "\t--oneshot, --nooneshot\n"
      "\t\tThe TMP175 and TMP75 feature a One-Shot Temperature Measurement Mode. When the device is in Shutdown Mode, writing 1 to the OS bit will start a single temperature conversion. The device will return to the shutdown state at the completion of the single conversion. This is useful to reduce power consumption in the TMP175 and TMP75 when continuous temperature monitoring is not required.\n\n"
      "\t--interruptmode, --comparatormode\n"
      "\t\tThe Thermostat Mode bit of the TMP175 and TMP75 indicates to the device whether to operate in Comparator Mode or Interrupt Mode (Alert pin). In Comparator mode, the ALERT pin is activated when the temperature equals or exceeds the value in the T(HIGH) register and it remains active until the temperature falls below the value in the T(LOW)register. In Interrupt mode, the ALERT pin is activated when the temperature exceeds T(HIGH) or goes below T(LOW) registers. The ALERT pin is cleared when the host controller reads the temperature register. For more information see the sensors datasheet.\n\n"
      "\t--activehigh, --activelow\n"
      "\t\tThe Polarity Bit of the TMP175 lets the user adjust the polarity of the ALERT pin output. If the POL bit is set to 0 (default), the ALERT pin becomes active low. When POL bit is set to 1, the ALERT pin becomes active high and the state of the ALERT pin is inverted.\n\n"
      "\t--faultqueue, -f=N\n"
      "\t\tA fault condition is defined as when the measured temperature exceeds the user-defined limits set in the THIGH and TLOW Registers. Additionally, the number of fault conditions required to generate an alert may be programmed using the Fault Queue. The Fault Queue is provided to prevent a false alert as a result of environmental noise. The Fault Queue requires consecutive fault measurements in order to trigger the alert function.\n\n"
      "\t--resolution, -r={0, 1, 2, 3}\n"
      "\t\tThe Converter Resolution Bits control the resolution of the internal analog-to-digital (ADC) converter. This control allows the user to maximize efficiency by programming for higher resolution or faster conversion time. \n\n"
      "\tR\tRESOLUTION\t(TYPICAL) CONVERSION TIME \n"
      "\t0\t0.5°C\t\t27.5 ms\n"
      "\t1\t0.25°C\t\t55 ms\n"
      "\t2\t0.125°C\t\t110 ms\n"
      "\t3\t0.0625°C\t220 ms\n"
      "\t--query, -q\n"
      "\t\tQueries the current cofiguration.\n\n"
      "\t--help\n"
      "\t\tPrint this help\n\n"
      "Author: Manuel Schneider manuelschneid3r@googles mail server\n"
      );
}

void err_write(int fd, const void *buf, size_t count) {
  if ((write(fd, buf, count)) != count) {
    printf("Error writing to i2c slave.\n");
    exit(1);
  }
}

void err_read(int fd, void *buf, size_t count) {
  if (read(fd, buf, count) != count) {
    printf("Unable to read from slave.\n");
    exit(1);
  }
}

struct config_t {
  int OS;   // Oneshot mode bool
  int RES;  // Resolution 0-3
  int FQ;   // Faultqueue 0-3
  int POL;  // Polarity bool
  int TM;   // Termostat xor
  int SD;   // Shutdownmode bool
};

int main(int argc, char **argv)
{
  static struct config_t config = {-1,-1,-1,-1,-1,-1};
  static int query = 0;
  static int c;
  static int help = 0;

  static struct option long_options[] =
  {
    {"oneshot",         no_argument,       &config.OS,  1},
    {"nooneshot",       no_argument,       &config.OS,  0},
    {"resolution",      required_argument, 0,           'r'},
    {"faultqueue",      required_argument, 0,           'f'},
    {"activehigh",      no_argument,       &config.POL, 1},
    {"activelow",       no_argument,       &config.POL, 0},
    {"interruptmode",   no_argument,       &config.TM,  1},
    {"comparatormode",  no_argument,       &config.TM,  0},
    {"shutdownmode",    no_argument,       &config.SD,  1},
    {"noshutdownmode",  no_argument,       &config.SD,  0},
    {"query",           no_argument,       0,           'q'},
    {"help",            no_argument,       &help,       1},
    {0, 0, 0, 0}
  };

  /*
   * Get the parameters and set the relevant flags for operation.
   */
  int option_index = 0;
  while ((c = getopt_long (argc, argv, "qr:f:",
                           long_options, &option_index)) != -1)
  {
    switch (c)
    {
    case 0:
      // getopt_long set flag to val
      break;
    case 'q':
      query = 1;
      break;
    case 'f':
      config.FQ = atoi(optarg);
      if (config.FQ < 0 || config.FQ > 3){
        printf("Invalid fault queue parameter\n");
        exit(1);
      }
      break;
    case 'r':
      config.RES = atoi(optarg);
      if (config.RES < 0 || config.RES > 3){
        printf("Invalid resoltion parameter\n");
        exit(1);
      }
      break;
    case '?':
      /* getopt_long already printed an error message. */
      return 1;
    default:
      abort ();
    }
  }

  // Print help if requested
  if (help==1) {
    print_help(argv[0]);
    exit(0);
  }

  // Print usage mesage in case of a wrong amount of params
  if ((argc-optind) != 2){
    print_usage(argv[0]);
    exit(1);
  }

  /*
   * Now start with the initializaton of the communication
   */
  // Open port for reading and writing
  int fd;
  if ((fd = open(argv[optind], O_RDWR)) < 0) {
    printf("Failed to open i2c port. Root?\n");
    exit(1);
  }

  // Set the port options and the address of the device we wish to speak to
  int  address = strtol(argv[optind+1], NULL, 0);
  if (ioctl(fd, I2C_SLAVE, address) < 0) {
    printf("Unable to get bus access to talk to slave.\n");
    exit(1);
  }


  /*
   * If the program was called with any of the configuration parameters get the
   * config resister, modifiy it and write it bac to the IC.
   */
  if (config.OS  != -1 || config.RES != -1 || config.FQ  != -1 ||
      config.POL != -1 || config.TM  != -1 || config.SD  != -1) {
    // Set register pointer on IC to config register
    unsigned char buf[2] = {1, 0};
    err_write(fd, buf, 1);

    // Read configuration register
    err_read(fd, buf+1, 1);

    // Set or unset the bits
    if (config.OS != -1)
      config.OS ? buf[1]|(1<<7) : buf[1]&~(1<<7);
    if (config.RES != -1){
      buf[1]&=~(3<<5); // Unset the resolution
      buf[1]|=config.RES<<5; //Set the resolution
    }
    if (config.FQ != -1){
      buf[1]&=~(3<<3); // Unset the FQ
      buf[1]|=config.FQ<<3; //Set the FQ
    }
    if (config.POL != -1)
      config.POL ? buf[1]|(1<<2) : buf[1]&~(1<<2) ;
    if (config.TM != -1)
      config.TM ? buf[1]|(1<<1) : buf[1]&~(1<<1) ;
    if (config.SD != -1)
      config.SD ? buf[1]|(1<<0) : buf[1]&~(1<<0) ;

    // Write the register back to the IC
    err_write(fd, buf, 2);

    // Query an pretty print the config
    query = 1;
  }


  /*
   * If this is a query prettyprint the config register to stdout
   * */
  if (query) {
    // Set register pointer on IC to config register
    unsigned char buf[2] = {1, 0};
    err_write(fd, buf, 1);

    // Read configuration register
    err_read(fd, buf+1, 1);

    // Pretty print config register
    int resolution = ((buf[1] & (3<<5)) >> 5);
    int fault_queue = ((buf[1] & (3<<3)) >> 3);
    printf("Oneshot:         %s\n", (buf[1] & (1<<7)) ? "Enabled" : "Disabled" );
    printf("Resolution:      %d (%.4f)\n", resolution, 1/pow(2, 1 + resolution));
    printf("Fault queue:     %d\n", fault_queue);
    printf("Alert pin:       Active %s\n", (buf[1] & (1<<2)) ? "high" : "low" );
    printf("Thermostat mode: %s mode\n", (buf[1] & (1<<1)) ? "Interrupt" : "Comparator" );
    printf("Shutdown mode:   %s\n", (buf[1] & (1<<0)) ? "Enabled" : "Disabled" );
    return 0;
  }

  /*
   * If this was not a config query get the temperature and quit
   */
  // Send register to read from. "0"/temperature register
  unsigned char buf[2]={0,0};
  err_write(fd, buf, 1);

  // Read back data into buf[]
  err_read(fd, buf, 2);

  // Compute the result
  signed short data = (buf[0]<<8)|buf[1];
  printf("%.1f\n", (float)data/256);

  return 0;
}

